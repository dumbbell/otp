%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 1996-2025. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%
-module(io_lib_format).
-moduledoc false.

-compile(nowarn_deprecated_catch).

-dialyzer([{nowarn_function, [iolist_to_bin/4]},
           no_improper_lists]).

%% Formatting functions of io library.

-export([fwrite/2,fwrite/3,
         fwrite_bin/2, fwrite_bin/3,
         fwrite_g/1,
         indentation/2,
         scan/2,unscan/1,
         build/1, build/2, build_bin/1, build_bin/2]).

%%  Format the arguments in Args after string Format. Just generate
%%  an error if there is an error in the arguments.
%%
%%  To do the printing command correctly we need to calculate the
%%  current indentation for everything before it. This may be very
%%  expensive, especially when it is not needed, so we first determine
%%  if, and for how long, we need to calculate the indentations. We do
%%  this by first collecting all the control sequences and
%%  corresponding arguments, then counting the print sequences and
%%  then building the output.  This method has some drawbacks, it does
%%  two passes over the format string and creates more temporary data,
%%  and it also splits the handling of the control characters into two
%%  parts.

-spec fwrite(Format, Data) -> io_lib:chars() when
      Format :: io:format(),
      Data :: [term()].

fwrite(Format, Args) ->
    build(scan(Format, Args)).

-spec fwrite(Format, Data, Options) -> io_lib:chars() when
      Format :: io:format(),
      Data :: [term()],
      Options :: [Option],
      Option :: {'chars_limit', CharsLimit},
      CharsLimit :: io_lib:chars_limit().

fwrite(Format, Args, Options) ->
    build(scan(Format, Args), Options).

%% Binary variants
-spec fwrite_bin(Format, Data) -> unicode:unicode_binary() when
      Format :: io:format(),
      Data :: [term()].

fwrite_bin(Format, Args) ->
    build_bin(scan(Format, Args)).

-spec fwrite_bin(Format, Data, Options) -> unicode:unicode_binary() when
      Format :: io:format(),
      Data :: [term()],
      Options :: [Option],
      Option :: {'chars_limit', CharsLimit},
      CharsLimit :: io_lib:chars_limit().

fwrite_bin(Format, Args, Options) ->
    build_bin(scan(Format, Args), Options).

%% Build the output text for a pre-parsed format list.

-spec build(FormatList) -> io_lib:chars() when
      FormatList :: [char() | io_lib:format_spec()].

build(Cs) ->
    build(Cs, []).

-spec build(FormatList, Options) -> io_lib:chars() when
      FormatList :: [char() | io_lib:format_spec()],
      Options :: [Option],
      Option :: {'chars_limit', CharsLimit},
      CharsLimit :: io_lib:chars_limit().

build(Cs, Options) ->
    CharsLimit = get_option(chars_limit, Options, -1),
    Res1 = build_small(Cs),
    {P, S, W, Other} = count_small(Res1),
    case P + S + W of
        0 ->
            Res1;
        NumOfLimited ->
            RemainingChars = sub(CharsLimit, Other),
            build_limited(Res1, P, NumOfLimited, RemainingChars, 0)
    end.

%% binary

-spec build_bin(FormatList) -> unicode:unicode_binary() when
      FormatList :: [char() | io_lib:format_spec()].
build_bin(Cs) ->
    build_bin(Cs, []).

-spec build_bin(FormatList, Options) -> unicode:unicode_binary() when
      FormatList :: [char() | io_lib:format_spec()],
      Options :: [Option],
      Option :: {'chars_limit', CharsLimit},
      CharsLimit :: io_lib:chars_limit().

build_bin(Cs, Options) ->
    CharsLimit = get_option(chars_limit, Options, -1),
    Res1 = build_small_bin(Cs),
    {P, S, W, Other} = count_small(Res1),
    case P + S + W of
        0 ->
            unicode:characters_to_binary(Res1);
        NumOfLimited ->
            RemainingChars = sub(CharsLimit, Other),
            Res = build_limited_bin(Res1, P, NumOfLimited, RemainingChars, 0),
            unicode:characters_to_binary(Res)
    end.

%% Parse all control sequences in the format string.

-spec scan(Format, Data) -> FormatList when
      Format :: io:format(),
      Data :: [term()],
      FormatList :: [char() | io_lib:format_spec()].

scan(Format, Args) when is_atom(Format) ->
    scan(atom_to_list(Format), Args);
scan(Format, Args) when is_binary(Format) ->
    scan(binary_to_list(Format), Args);
scan(Format, Args) ->
    collect(Format, Args).

%% Revert a pre-parsed format list to a plain character list and a
%% list of arguments.

-spec unscan(FormatList) -> {Format, Data} when
      FormatList :: [char() | io_lib:format_spec()],
      Format :: io:format(),
      Data :: [term()].

unscan(Cs) ->
    {print(Cs), args(Cs)}.

args([#{args := As, maps_order := O} | Cs]) when is_function(O, 2); O =:= reversed ->
    [O | As] ++ args(Cs);
args([#{args := As} | Cs]) ->
    As ++ args(Cs);
args([_C | Cs]) ->
    args(Cs);
args([]) ->
    [].

print([#{control_char := C, width := F, adjust := Ad, precision := P,
         pad_char := Pad, encoding := Encoding, strings := Strings
        } = Map | Cs]) ->
    MapsOrder = maps:get(maps_order, Map, undefined),
    print(C, F, Ad, P, Pad, Encoding, Strings, MapsOrder) ++ print(Cs);
print([C | Cs]) when is_integer(C) ->
    [C | print(Cs)];
print([]) ->
    [].

print(C, F, Ad, P, Pad, Encoding, Strings, MapsOrder) ->
    [$~] ++ print_field_width(F, Ad) ++ print_precision(P, Pad) ++
        print_pad_char(Pad) ++ print_encoding(Encoding) ++
        print_strings(Strings) ++ print_maps_order(MapsOrder) ++
        [C].

print_field_width(none, _Ad) -> "";
print_field_width(F, left) -> integer_to_list(-F);
print_field_width(F, right) -> integer_to_list(F).

print_precision(none, $\s) -> "";
print_precision(none, _Pad) -> ".";  % pad must be second dot
print_precision(P, _Pad) -> [$. | integer_to_list(P)].

print_pad_char($\s) -> ""; % default, no need to make explicit
print_pad_char(Pad) -> [$., Pad].

print_encoding(unicode) -> "t";
print_encoding(latin1) -> "".

print_strings(false) -> "l";
print_strings(true) -> "".

print_maps_order(undefined) -> "";
print_maps_order(ordered) -> "k";
print_maps_order(reversed) -> "K";
print_maps_order(CmpFun) when is_function(CmpFun, 2) -> "K".

collect([$~|Fmt0], Args0) ->
    {C,Fmt1,Args1} = collect_cseq(Fmt0, Args0),
    [C|collect(Fmt1, Args1)];
collect([C|Fmt], Args) ->
    [C|collect(Fmt, Args)];
collect([], []) -> [].

collect_cseq(Fmt0, Args0) ->
    {F,Ad,Fmt1,Args1} = field_width(Fmt0, Args0),
    {P,Fmt2,Args2} = precision(Fmt1, Args1),
    {Pad,Fmt3,Args3} = pad_char(Fmt2, Args2),
    Spec0 = #{width => F,
              adjust => Ad,
              precision => P,
              pad_char => Pad,
              encoding => latin1,
              strings => true,
              maps_order => undefined},
    {Spec1,Fmt4,Args4} = modifiers(Fmt3, Args3, Spec0),
    {C,As,Fmt5,Args5} = collect_cc(Fmt4, Args4),
    Spec2 = Spec1#{control_char => C, args => As},
    {Spec2,Fmt5,Args5}.

modifiers([$t|Fmt], Args, Spec) ->
    modifiers(Fmt, Args, Spec#{encoding => unicode});
modifiers([$l|Fmt], Args, Spec) ->
    modifiers(Fmt, Args, Spec#{strings => false});
modifiers([$k|Fmt], Args, Spec) ->
    modifiers(Fmt, Args, Spec#{maps_order => ordered});
modifiers([$K|Fmt], [MapsOrder | Args], Spec) ->
    modifiers(Fmt, Args, Spec#{maps_order => MapsOrder});
modifiers(Fmt, Args, Spec) ->
    {Spec, Fmt, Args}.

field_width([$-|Fmt0], Args0) ->
    {F,Fmt,Args} = field_value(Fmt0, Args0),
    field_width(-F, Fmt, Args);
field_width(Fmt0, Args0) ->
    {F,Fmt,Args} = field_value(Fmt0, Args0),
    field_width(F, Fmt, Args).

field_width(F, Fmt, Args) when F < 0 ->
    {-F,left,Fmt,Args};
field_width(F, Fmt, Args) when F >= 0 ->
    {F,right,Fmt,Args}.

precision([$.|Fmt], Args) ->
    field_value(Fmt, Args);
precision(Fmt, Args) ->
    {none,Fmt,Args}.

field_value([$*|Fmt], [A|Args]) when is_integer(A) ->
    {A,Fmt,Args};
field_value([C|Fmt], Args) when is_integer(C), C >= $0, C =< $9 ->
    field_value([C|Fmt], Args, 0);
field_value(Fmt, Args) ->
    {none,Fmt,Args}.

field_value([C|Fmt], Args, F) when is_integer(C), C >= $0, C =< $9 ->
    field_value(Fmt, Args, 10*F + (C - $0));
field_value(Fmt, Args, F) ->		%Default case
    {F,Fmt,Args}.

pad_char([$.,$*|Fmt], [Pad|Args]) -> {Pad,Fmt,Args};
pad_char([$.,Pad|Fmt], Args) -> {Pad,Fmt,Args};
pad_char(Fmt, Args) -> {$\s,Fmt,Args}.

%% collect_cc([FormatChar], [Argument]) ->
%%	{Control,[ControlArg],[FormatChar],[Arg]}.
%%  Here we collect the argments for each control character.
%%  Be explicit to cause failure early.

collect_cc([$w|Fmt], [A|Args]) -> {$w,[A],Fmt,Args};
collect_cc([$p|Fmt], [A|Args]) -> {$p,[A],Fmt,Args};
collect_cc([$W|Fmt], [A,Depth|Args]) -> {$W,[A,Depth],Fmt,Args};
collect_cc([$P|Fmt], [A,Depth|Args]) -> {$P,[A,Depth],Fmt,Args};
collect_cc([$s|Fmt], [A|Args]) -> {$s,[A],Fmt,Args};
collect_cc([$e|Fmt], [A|Args]) -> {$e,[A],Fmt,Args};
collect_cc([$f|Fmt], [A|Args]) -> {$f,[A],Fmt,Args};
collect_cc([$g|Fmt], [A|Args]) -> {$g,[A],Fmt,Args};
collect_cc([$b|Fmt], [A|Args]) -> {$b,[A],Fmt,Args};
collect_cc([$B|Fmt], [A|Args]) -> {$B,[A],Fmt,Args};
collect_cc([$x|Fmt], [A,Prefix|Args]) -> {$x,[A,Prefix],Fmt,Args};
collect_cc([$X|Fmt], [A,Prefix|Args]) -> {$X,[A,Prefix],Fmt,Args};
collect_cc([$+|Fmt], [A|Args]) -> {$+,[A],Fmt,Args};
collect_cc([$#|Fmt], [A|Args]) -> {$#,[A],Fmt,Args};
collect_cc([$c|Fmt], [A|Args]) -> {$c,[A],Fmt,Args};
collect_cc([$~|Fmt], Args) when is_list(Args) -> {$~,[],Fmt,Args};
collect_cc([$n|Fmt], Args) when is_list(Args) -> {$n,[],Fmt,Args};
collect_cc([$i|Fmt], [A|Args]) -> {$i,[A],Fmt,Args}.

%% count_small([ControlC]) -> Count.
%%  Count the number of big (pPwWsS) print requests and
%%  number of characters of other print (small) requests.

count_small(Cs) ->
    count_small(Cs, #{p => 0, s => 0, w => 0, other => 0}).

count_small([#{control_char := $p}|Cs], #{p := P} = Cnts) ->
    count_small(Cs, Cnts#{p := P + 1});
count_small([#{control_char := $P}|Cs], #{p := P} = Cnts) ->
    count_small(Cs, Cnts#{p := P + 1});
count_small([#{control_char := $w}|Cs], #{w := W} = Cnts) ->
    count_small(Cs, Cnts#{w := W + 1});
count_small([#{control_char := $W}|Cs], #{w := W} = Cnts) ->
    count_small(Cs, Cnts#{w := W + 1});
count_small([#{control_char := $s}|Cs], #{w := W} = Cnts) ->
    count_small(Cs, Cnts#{w := W + 1});
count_small([S|Cs], #{other := Other} = Cnts)
  when is_list(S) ->
    count_small(Cs, Cnts#{other := Other + io_lib:chars_length(S)});
count_small([S|Cs], #{other := Other} = Cnts)
  when is_binary(S) ->
    count_small(Cs, Cnts#{other := Other + string:length(S)});
count_small([C|Cs], #{other := Other} = Cnts) when is_integer(C) ->
    count_small(Cs, Cnts#{other := Other + 1});
count_small([], #{p := P, s := S, w := W, other := Other}) ->
    {P, S, W, Other}.

%% build_small([Control]) -> io_lib:chars().
%%  Interpret the control structures, but only the small ones.
%%  The big ones are saved for later.
%% build_limited([Control], NumberOfPps, NumberOfLimited,
%%               CharsLimit, Indentation)
%%  Interpret the control structures. Count the number of print
%%  remaining and only calculate indentation when necessary. Must also
%%  be smart when calculating indentation for characters in format.

build_small([#{control_char := C, args := As, width := F, adjust := Ad,
               precision := P, pad_char := Pad, encoding := Enc}=CC | Cs]) ->
    case control_small(C, As, F, Ad, P, Pad, Enc) of
        not_small -> [CC | build_small(Cs)];
        S -> lists:flatten(S) ++ build_small(Cs)
    end;
build_small([C|Cs]) -> [C|build_small(Cs)];
build_small([]) -> [].

build_limited([#{control_char := C, args := As, width := F, adjust := Ad,
                 precision := P, pad_char := Pad, encoding := Enc,
                 strings := Str} = Map | Cs],
              NumOfPs0, Count0, MaxLen0, I) ->
    Ord = maps:get(maps_order, Map, undefined),
    MaxChars = if
                   MaxLen0 < 0 -> MaxLen0;
                   true -> MaxLen0 div Count0
               end,
    S = control_limited(C, As, F, Ad, P, Pad, Enc, Str, Ord, MaxChars, I),
    NumOfPs = decr_pc(C, NumOfPs0),
    Count = Count0 - 1,
    MaxLen = if
                 MaxLen0 < 0 -> % optimization
                     MaxLen0;
                 true ->
                     Len = io_lib:chars_length(S),
                     sub(MaxLen0, Len)
             end,
    if
	NumOfPs > 0 ->
            [S|build_limited(Cs, NumOfPs, Count, MaxLen, indentation(S, I))];
	true ->
            [S|build_limited(Cs, NumOfPs, Count, MaxLen, I)]
    end;
build_limited([$\n|Cs], NumOfPs, Count, MaxLen, _I) ->
    [$\n|build_limited(Cs, NumOfPs, Count, MaxLen, 0)];
build_limited([$\t|Cs], NumOfPs, Count, MaxLen, I) ->
    [$\t|build_limited(Cs, NumOfPs, Count, MaxLen, ((I + 8) div 8) * 8)];
build_limited([C|Cs], NumOfPs, Count, MaxLen, I) ->
    [C|build_limited(Cs, NumOfPs, Count, MaxLen, I+1)];
build_limited([], _, _, _, _) -> [].

decr_pc($p, Pc) -> Pc - 1;
decr_pc($P, Pc) -> Pc - 1;
decr_pc(_, Pc) -> Pc.

build_small_bin([#{control_char := C, args := As, width := F, adjust := Ad,
                   precision := P, pad_char := Pad, encoding := Enc}=CC | Cs]) ->
    case control_small(C, As, F, Ad, P, Pad, Enc) of
        not_small ->
            [CC | build_small_bin(Cs)];
        [$\n|_] = NL ->
            [NL | build_small_bin(Cs)];
        S ->
            SBin = unicode:characters_to_binary(S, Enc, unicode),
            true = is_binary(SBin),
            [SBin | build_small_bin(Cs)]
    end;
build_small_bin([$\t|Cs]) ->
    [$\t | build_small_bin(Cs)];
build_small_bin([C|Cs]) ->
    [C | build_small_bin(Cs)];
build_small_bin([]) ->
    [].

build_limited_bin([#{control_char := C, args := As, width := F, adjust := Ad,
                     precision := P, pad_char := Pad, encoding := Enc,
                     strings := Str} = Map | Cs],
                  NumOfPs0, Count0, MaxLen0, I0) ->
    Ord = maps:get(maps_order, Map, undefined),
    MaxChars = if
                   MaxLen0 < 0 -> MaxLen0;
                   true -> MaxLen0 div Count0
               end,
    {S, Sz, I} = control_limited_bin(C, As, F, Ad, P, Pad, Enc, Str, Ord, MaxChars, I0),
    NumOfPs = decr_pc(C, NumOfPs0),
    Count = Count0 - 1,
    MaxLen = if
                 MaxLen0 < 0 -> MaxLen0; % optimization
                 Sz < 0 -> sub(MaxLen0, string:length(S));
                 true -> sub(MaxLen0, Sz)
             end,
    if
	NumOfPs > 0, I < 0 ->
            [S|build_limited_bin(Cs, NumOfPs, Count, MaxLen, indentation(S, I0))];
	true ->
            [S|build_limited_bin(Cs, NumOfPs, Count, MaxLen, I)]
    end;
build_limited_bin([[$\n|_]=NL|Cs], NumOfPs, Count, MaxLen, _I) ->
    [NL|build_limited_bin(Cs, NumOfPs, Count, MaxLen, 0)];
build_limited_bin([$\t|Cs], NumOfPs, Count, MaxLen, I) ->
    [$\t|build_limited_bin(Cs, NumOfPs, Count, MaxLen, ((I + 8) div 8) * 8)];
build_limited_bin([C|Cs], NumOfPs, Count, MaxLen, I) when is_integer(C) ->
    [C|build_limited_bin(Cs, NumOfPs, Count, MaxLen, 1+I)];
build_limited_bin([Bin|Cs], NumOfPs, Count, MaxLen, I) when is_binary(Bin) ->
    [Bin|build_limited_bin(Cs, NumOfPs, Count, MaxLen, byte_size(Bin)+I)];
build_limited_bin([], _, _, _, _) -> [].


%%  Calculate the indentation of the end of a string given its start
%%  indentation. We assume tabs at 8 cols.

-spec indentation(String, StartIndent) -> integer() when
      String :: unicode:chardata(),
      StartIndent :: integer().

indentation([$\n|Cs], _I) ->
    indentation(Cs, 0);
indentation([$\t|Cs], I) ->
    indentation(Cs, ((I + 8) div 8) * 8);
indentation([C|Cs], I) when is_integer(C) ->
    indentation(Cs, I+1);
indentation([C|Cs], I) ->
    indentation(Cs, indentation(C, I));
indentation(Bin, I0) when is_binary(Bin) ->
    indentation_bin(Bin, I0);
indentation([], I) ->
    I.

indentation_bin(Bin, I) ->
    indentation_bin(Bin, Bin, 0, 0, I).

indentation_bin(<<$\n, Cs/binary>>, Orig, _Start, N,_I) ->
    indentation_bin(Cs, Orig, N+1, 0, 0);
indentation_bin(<<$\t, Cs/binary>>, Orig, Start, N, I0) ->
    Part = binary:part(Orig, Start, N),
    PSz = string:length(Part),
    indentation_bin(Cs, Orig, N+1, N+1, ((I0+PSz + 8) div 8) * 8);
indentation_bin(<<_, Cs/binary>>, Orig, Start, N, I) ->
    indentation_bin(Cs, Orig, Start, N+1, I);
indentation_bin(<<>>, Orig, Start, N, I) ->
    Part = binary:part(Orig, Start, N),
    PSz = string:length(Part),
    I + PSz.


%% control_small(FormatChar, [Argument], FieldWidth, Adjust, Precision,
%%               PadChar, Encoding) -> String
%% control_limited(FormatChar, [Argument], FieldWidth, Adjust, Precision,
%%                 PadChar, Encoding, StringP, ChrsLim, Indentation) -> String
%%  These are the dispatch functions for the various formatting controls.

control_small($s, [A], F, Adj, P, Pad, latin1=Enc) when is_atom(A) ->
    L = iolist_to_chars(atom_to_list(A)),
    string(L, F, Adj, P, Pad, Enc);
control_small($s, [A], F, Adj, P, Pad, unicode=Enc) when is_atom(A) ->
    string(atom_to_list(A), F, Adj, P, Pad, Enc);
control_small($e, [A], F, Adj, P, Pad, _Enc) when is_float(A) ->
    fwrite_e(A, F, Adj, P, Pad);
control_small($f, [A], F, Adj, P, Pad, _Enc) when is_float(A) ->
    fwrite_f(A, F, Adj, P, Pad);
control_small($g, [A], F, Adj, P, Pad, _Enc) when is_float(A) ->
    fwrite_g(A, F, Adj, P, Pad);
control_small($b, [A], F, Adj, P, Pad, _Enc) when is_integer(A) ->
    unprefixed_integer(A, F, Adj, base(P), Pad, true);
control_small($B, [A], F, Adj, P, Pad, _Enc) when is_integer(A) ->
    unprefixed_integer(A, F, Adj, base(P), Pad, false);
control_small($x, [A,Prefix], F, Adj, P, Pad, _Enc) when is_integer(A),
                                                         is_atom(Prefix) ->
    prefixed_integer(A, F, Adj, base(P), Pad, atom_to_list(Prefix), true);
control_small($x, [A,Prefix], F, Adj, P, Pad, _Enc) when is_integer(A) ->
    true = io_lib:deep_char_list(Prefix), %Check if Prefix a character list
    prefixed_integer(A, F, Adj, base(P), Pad, Prefix, true);
control_small($X, [A,Prefix], F, Adj, P, Pad, _Enc) when is_integer(A),
                                                         is_atom(Prefix) ->
    prefixed_integer(A, F, Adj, base(P), Pad, atom_to_list(Prefix), false);
control_small($X, [A,Prefix], F, Adj, P, Pad, _Enc) when is_integer(A) ->
    true = io_lib:deep_char_list(Prefix), %Check if Prefix a character list
    prefixed_integer(A, F, Adj, base(P), Pad, Prefix, false);
control_small($+, [A], F, Adj, P, Pad, _Enc) when is_integer(A) ->
    Base = base(P),
    Prefix = [integer_to_list(Base), $#],
    prefixed_integer(A, F, Adj, Base, Pad, Prefix, true);
control_small($#, [A], F, Adj, P, Pad, _Enc) when is_integer(A) ->
    Base = base(P),
    Prefix = [integer_to_list(Base), $#],
    prefixed_integer(A, F, Adj, Base, Pad, Prefix, false);
control_small($c, [A], F, Adj, P, Pad, unicode) when is_integer(A) ->
    char(A, F, Adj, P, Pad);
control_small($c, [A], F, Adj, P, Pad, _Enc) when is_integer(A) ->
    char(A band 255, F, Adj, P, Pad);
control_small($~, [], F, Adj, P, Pad, _Enc) -> char($~, F, Adj, P, Pad);
control_small($n, [], F, Adj, P, Pad, _Enc) -> newline(F, Adj, P, Pad);
control_small($i, [_A], _F, _Adj, _P, _Pad, _Enc) -> [];
control_small(_C, _As, _F, _Adj, _P, _Pad, _Enc) -> not_small.

control_limited($s, [L0], F, Adj, P, Pad, Enc, _Str, _Ord, CL, _I) ->
    if Enc =:= latin1 ->
            L = iolist_to_chars(L0, F, CL),
            string(L, limit_field(F, CL), Adj, P, Pad, Enc);
       Enc =:= unicode ->
            L = cdata_to_chars(L0, F, CL),
            uniconv(string(L, limit_field(F, CL), Adj, P, Pad, Enc))
    end;
control_limited($w, [A], F, Adj, P, Pad, Enc, _Str, Ord, CL, _I) ->
    Chars = io_lib:write(A, -1, Enc, Ord, CL),
    term(Chars, F, Adj, P, Pad, Enc);
control_limited($p, [A], F, Adj, P, Pad, Enc, Str, Ord, CL, I) ->
    print(A, -1, F, Adj, P, Pad, Enc, list, Str, Ord, CL, I);
control_limited($W, [A,Depth], F, Adj, P, Pad, Enc, _Str, Ord, CL, _I)
  when is_integer(Depth) ->
    Chars = io_lib:write(A, Depth, Enc, Ord, CL),
    term(Chars, F, Adj, P, Pad, Enc);
control_limited($P, [A,Depth], F, Adj, P, Pad, Enc, Str, Ord, CL, I)
  when is_integer(Depth) ->
    print(A, Depth, F, Adj, P, Pad, Enc, list, Str, Ord, CL, I).

control_limited_bin($s, [L0], F, Adj, P, Pad, Enc, _Str, _Ord, CL, _I) ->
    {B, Sz} = iolist_to_bin(L0, F, CL, Enc),
    string_bin(B, Sz, limit_field(F, CL), Adj, P, Pad, Enc);
control_limited_bin($w, [A], F, Adj, P, Pad, Enc, _Str, Ord, CL, I) ->
    {Chars, Sz} = io_lib:write_bin(A, -1, Enc, Ord, CL),
    term_bin(Chars, F, Adj, P, Pad, Enc, Sz, I);
control_limited_bin($p, [A], F, Adj, P, Pad, Enc, Str, Ord, CL, I) ->
    print(A, -1, F, Adj, P, Pad, Enc, binary, Str, Ord, CL, I);
control_limited_bin($W, [A,Depth], F, Adj, P, Pad, Enc, _Str, Ord, CL, I)
  when is_integer(Depth) ->
    {Chars, Sz} = io_lib:write_bin(A, Depth, Enc, Ord, CL),
    term_bin(Chars, F, Adj, P, Pad, Enc, Sz, I);
control_limited_bin($P, [A,Depth], F, Adj, P, Pad, Enc, Str, Ord, CL, I)
  when is_integer(Depth) ->
    print(A, Depth, F, Adj, P, Pad, Enc, binary, Str, Ord, CL, I).

term_bin(T, none, _Adj, none, _Pad, _Enc, Sz, I) ->
    {T, Sz, Sz+I};
term_bin(T, none, Adj, P, Pad, Enc, Sz, I) ->
    term_bin(T, P, Adj, P, Pad, Enc, Sz, I);
term_bin(T, F, Adj, P0, Pad, _Enc, Sz, I) ->
    P = erlang:min(Sz, case P0 of none -> F; _ -> min(P0, F) end),
    if
	Sz > P ->
	    {adjust(chars($*, P), chars(Pad, F-P), Adj), F, I+F};
	F >= P ->
            {adjust(T, chars(Pad, F-Sz), Adj), F, I+F}
    end.

-ifdef(UNICODE_AS_BINARIES).
uniconv(C) ->
    unicode:characters_to_binary(C,unicode).
-else.
uniconv(C) ->
    C.
-endif.
%% Default integer base
base(none) ->
    10;
base(B) when is_integer(B) ->
    B.

%% term(TermList, Field, Adjust, Precision, PadChar)
%%  Output the characters in a term.
%%  Adjust the characters within the field if length less than Max padding
%%  with PadChar.

term(T, none, _Adj, none, _Pad, _Enc) ->
    T;
term(T, none, Adj, P, Pad, Enc) ->
    term(T, P, Adj, P, Pad, Enc);
term(T, F, Adj, P0, Pad, Enc) ->
    L = case Enc =:= latin1 of
            true  -> io_lib:chars_length(T);
            false -> string:length(T)
        end,
    P = erlang:min(L, case P0 of none -> F; _ -> min(P0, F) end),
    if
	L > P ->
	    adjust(chars($*, P), chars(Pad, F-P), Adj);
	F >= P ->
	    adjust(T, chars(Pad, F-L), Adj)
    end.

%% print(Term, Depth, Field, Adjust, Precision, PadChar, Encoding,
%%       Indentation)
%% Print a term. Field width sets maximum line length, Precision sets
%% initial indentation.

print(T, D, none, Adj, P, Pad, E, Type, Str, Ord, ChLim, I) ->
    print(T, D, 80, Adj, P, Pad, E, Type, Str, Ord, ChLim, I);
print(T, D, F, Adj, none, Pad, E, Type, Str, Ord, ChLim, I) ->
    print(T, D, F, Adj, I+1, Pad, E, Type, Str, Ord, ChLim, I);
print(T, D, F, right, P, _Pad, Enc, list, Str, Ord, ChLim, _I) ->
    Options = [{chars_limit, ChLim},
               {column, P},
               {line_length, F},
               {depth, D},
               {encoding, Enc},
               {strings, Str},
               {maps_order, Ord}
              ],
    io_lib_pretty:print(T, Options);
print(T, D, F, right, P, _Pad, Enc, binary, Str, Ord, ChLim, I) ->
    Options = #{chars_limit => ChLim,
                column => P,
                line_length => F,
                depth => D,
                encoding => Enc,
                strings => Str,
                maps_order => Ord
               },
    {Bin, Sz, Col} = Res = io_lib_pretty:print_bin(T, Options),
    case Col > 0 of
        true  -> Res;
        false -> {Bin, Sz, I - Col}
    end.

%% fwrite_e(Float, Field, Adjust, Precision, PadChar)

fwrite_e(Fl, none, Adj, none, Pad) ->		%Default values
    fwrite_e(Fl, none, Adj, 6, Pad);
fwrite_e(Fl, none, _Adj, P, _Pad) when P >= 2 ->
    float_e(Fl, float_data(Fl), P);
fwrite_e(Fl, F, Adj, none, Pad) ->
    fwrite_e(Fl, F, Adj, 6, Pad);
fwrite_e(Fl, F, Adj, P, Pad) when P >= 2 ->
    term(float_e(Fl, float_data(Fl), P), F, Adj, F, Pad, latin1).

float_e(Fl, Fd, P) ->
    signbit(Fl) ++ abs_float_e(abs(Fl), Fd, P).

abs_float_e(_Fl, {Ds,E}, P) ->
    case float_man(Ds, 1, P-1) of
	{[$0|Fs],true} -> [[$1|Fs]|float_exp(E)];
	{Fs,false} -> [Fs|float_exp(E-1)]
    end.

%% float_man([Digit], Icount, Dcount) -> {[Char],CarryFlag}.
%%  Generate the characters in the mantissa from the digits with Icount
%%  characters before the '.' and Dcount decimals. Handle carry and let
%%  caller decide what to do at top.

float_man(Ds, 0, Dc) ->
    {Cs,C} = float_man(Ds, Dc),
    {[$.|Cs],C};
float_man([D|Ds], I, Dc) ->
    case float_man(Ds, I-1, Dc) of
	{Cs,true} when D =:= $9 -> {[$0|Cs],true};
	{Cs,true} -> {[D+1|Cs],false};
	{Cs,false} -> {[D|Cs],false}
    end;
float_man([], I, Dc) ->				%Pad with 0's
    {lists:duplicate(I, $0) ++ [$.|lists:duplicate(Dc, $0)],false}.

float_man([D|_], 0) when D >= $5 -> {[],true};
float_man([_|_], 0) -> {[],false};
float_man([D|Ds], Dc) ->
    case float_man(Ds, Dc-1) of
	{Cs,true} when D =:= $9 -> {[$0|Cs],true};
	{Cs,true} -> {[D+1|Cs],false}; 
	{Cs,false} -> {[D|Cs],false}
    end;
float_man([], Dc) -> {lists:duplicate(Dc, $0),false}.	%Pad with 0's

%% float_exp(Exponent) -> [Char].
%%  Generate the exponent of a floating point number. Always include sign.

float_exp(E) when E >= 0 ->
    [$e,$+|integer_to_list(E)];
float_exp(E) ->
    [$e|integer_to_list(E)].

%% fwrite_f(FloatData, Field, Adjust, Precision, PadChar)

fwrite_f(Fl, none, Adj, none, Pad) ->		%Default values
    fwrite_f(Fl, none, Adj, 6, Pad);
fwrite_f(Fl, none, _Adj, P, _Pad) when P >= 1 ->
    float_f(Fl, float_data(Fl), P);
fwrite_f(Fl, F, Adj, none, Pad) ->
    fwrite_f(Fl, F, Adj, 6, Pad);
fwrite_f(Fl, F, Adj, P, Pad) when P >= 1 ->
    term(float_f(Fl, float_data(Fl), P), F, Adj, F, Pad, latin1).

float_f(Fl, Fd, P) ->
    signbit(Fl) ++ abs_float_f(abs(Fl), Fd, P).

abs_float_f(Fl, {Ds,E}, P) when E =< 0 ->
    abs_float_f(Fl, {lists:duplicate(-E+1, $0)++Ds,1}, P);	%Prepend enough 0's
abs_float_f(_Fl, {Ds,E}, P) ->
    case float_man(Ds, E, P) of
	{Fs,true} -> "1" ++ Fs;			%Handle carry
	{Fs,false} -> Fs
    end.

%% signbit(Float) -> [$-] | []

signbit(Fl) when Fl < 0.0 -> [$-];
signbit(Fl) when Fl > 0.0 -> [];
signbit(Fl) ->
    case <<Fl/float>> of
        <<1:1,_:63>> -> [$-];
        _ -> []
    end.

%% float_data([FloatChar]) -> {[Digit],Exponent}

float_data(Fl) ->
    float_data(float_to_list(Fl), []).

float_data([$e|E], Ds) ->
    {lists:reverse(Ds),list_to_integer(E)+1};
float_data([D|Cs], Ds) when D >= $0, D =< $9 ->
    float_data(Cs, [D|Ds]);
float_data([_|Cs], Ds) ->
    float_data(Cs, Ds).

%%  Returns a correctly rounded string that converts to Float when
%%  read back with list_to_float/1.

-spec fwrite_g(float()) -> string().
fwrite_g(Float) ->
    float_to_list(Float, [short]).

%% fwrite_g(Float, Field, Adjust, Precision, PadChar)
%%  Use the f form if Float is >= 0.1 and < 1.0e4, 
%%  and the prints correctly in the f form, else the e form.
%%  Precision always means the # of significant digits.

fwrite_g(Fl, F, Adj, none, Pad) ->
    fwrite_g(Fl, F, Adj, 6, Pad);
fwrite_g(Fl, F, Adj, P, Pad) when P >= 1 ->
    A = abs(Fl),
    E = if A < 1.0e-1 -> -2;
	   A < 1.0e0  -> -1;
	   A < 1.0e1  -> 0;
	   A < 1.0e2  -> 1;
	   A < 1.0e3  -> 2;
	   A < 1.0e4  -> 3;
	   true       -> fwrite_f
	end,
    if  P =< 1, E =:= -1;
	P-1 > E, E >= -1 ->
	    fwrite_f(Fl, F, Adj, P-1-E, Pad);
	P =< 1 ->
	    fwrite_e(Fl, F, Adj, 2, Pad);
	true ->
	    fwrite_e(Fl, F, Adj, P, Pad)
    end.


iolist_to_chars(Cs, F, CharsLimit) when CharsLimit < 0; CharsLimit >= F ->
    iolist_to_chars(Cs);
iolist_to_chars(Cs, _, CharsLimit) ->
    limit_iolist_to_chars(Cs, sub(CharsLimit, 3), [], normal). % three dots

iolist_to_chars([C|Cs]) when is_integer(C), C >= $\000, C =< $\377 ->
    [C | iolist_to_chars(Cs)];
iolist_to_chars([I|Cs]) ->
    [iolist_to_chars(I) | iolist_to_chars(Cs)];
iolist_to_chars([]) ->
    [];
iolist_to_chars(B) when is_binary(B) ->
    binary_to_list(B).

limit_iolist_to_chars(Cs, 0, S, normal) ->
    L = limit_iolist_to_chars(Cs, 4, S, final),
    case iolist_size(L) of
        N when N < 4 -> L;
        4 -> "..."
    end;
limit_iolist_to_chars(_Cs, 0, _S, final) -> [];
limit_iolist_to_chars([C|Cs], Limit, S, Mode) when C >= $\000, C =< $\377 ->
    [C | limit_iolist_to_chars(Cs, Limit - 1, S, Mode)];
limit_iolist_to_chars([I|Cs], Limit, S, Mode) ->
    limit_iolist_to_chars(I, Limit, [Cs|S], Mode);
limit_iolist_to_chars([], _Limit, [], _Mode) ->
    [];
limit_iolist_to_chars([], Limit, [Cs|S], Mode) ->
    limit_iolist_to_chars(Cs, Limit, S, Mode);
limit_iolist_to_chars(B, Limit, S, Mode) when is_binary(B) ->
    case byte_size(B) of
        Sz when Sz > Limit ->
            {B1, B2} = split_binary(B, Limit),
            [binary_to_list(B1) | limit_iolist_to_chars(B2, 0, S, Mode)];
        Sz ->
            [binary_to_list(B) | limit_iolist_to_chars([], Limit-Sz, S, Mode)]
    end.

cdata_to_chars(Cs, F, CharsLimit) when CharsLimit < 0; CharsLimit >= F ->
    cdata_to_chars(Cs);
cdata_to_chars(Cs, _, CharsLimit) ->
    limit_cdata_to_chars(Cs, sub(CharsLimit, 3), normal). % three dots

cdata_to_chars([C|Cs]) when is_integer(C), C >= $\000 ->
    [C | cdata_to_chars(Cs)];
cdata_to_chars([I|Cs]) ->
    [cdata_to_chars(I) | cdata_to_chars(Cs)];
cdata_to_chars([]) ->
    [];
cdata_to_chars(B) when is_binary(B) ->
    case catch unicode:characters_to_list(B) of
        L when is_list(L) -> L;
        _ -> binary_to_list(B)
    end.

limit_cdata_to_chars(Cs, 0, normal) ->
    L = limit_cdata_to_chars(Cs, 4, final),
    case string:length(L) of
        N when N < 4 -> L;
        4 -> "..."
    end;
limit_cdata_to_chars(_Cs, 0, final) -> [];
limit_cdata_to_chars(Cs, Limit, Mode) ->
    case string:next_grapheme(Cs) of
        {error, <<C,Cs1/binary>>} ->
            %% This is how ~ts handles Latin1 binaries with option
            %% chars_limit.
            [C | limit_cdata_to_chars(Cs1, Limit - 1, Mode)];
        {error, [C|Cs1]} -> % not all versions of module string return this
            [C | limit_cdata_to_chars(Cs1, Limit - 1, Mode)];
        [] ->
            [];
        [GC|Cs1] ->
            [GC | limit_cdata_to_chars(Cs1, Limit - 1, Mode)]
    end.

iolist_to_bin(L, F, CharsLimit, latin1) when CharsLimit < 0; CharsLimit >= F ->
    Bin = unicode:characters_to_binary(L, latin1, unicode),
    {Bin, iolist_size(L)};
iolist_to_bin(L, F, CharsLimit, unicode) when CharsLimit < 0; CharsLimit >= F ->
    case unicode:characters_to_binary(L) of
        Bin when is_binary(Bin) ->
            {Bin, undefined};
        {error, Ok, Bad} ->
            %% Try latin1, strange allowing mixing latin1 and utf8
            %% but we handled it before for unknown reason.
            {Bin, _} = iolist_to_bin(Bad, F, CharsLimit, latin1),
            {iolist_to_binary([Ok|Bin]), undefined}
    end;
iolist_to_bin(L, _, CharsLimit, Enc) ->
    {Acc, Sz, _Limit, Rest} = limit_iolist_to_bin(L, sub(CharsLimit, 3), Enc, 0, <<>>),
    case string:is_empty(Rest) of
        true ->
            {Acc, Sz};
        false ->
            {Cont, Size, _, _} = limit_iolist_to_bin(Rest, 4, Enc, 0, <<>>),
            if Size < 4 ->
                    {<<Acc/binary, Cont/binary>>, Sz+Size};
               true ->
                    {<<Acc/binary, "...">>, Sz+3}
            end
    end.

limit_iolist_to_bin(Cs, 0, _, Size, Acc) ->
    {Acc, Size, 0, Cs};
limit_iolist_to_bin([C|Cs], Limit, latin1, Size, Acc)
  when C >= $\000, C =< $\377 ->
    limit_iolist_to_bin(Cs, Limit-1, latin1, Size+1, <<Acc/binary, C/utf8>>);
limit_iolist_to_bin(Bin0, Limit, latin1, Size0, Acc)
  when is_binary(Bin0) ->
    case byte_size(Bin0) of
        Sz when Sz > Limit ->
            {B1, B2} = split_binary(Bin0, Limit),
            Bin = unicode:characters_to_binary(B1, latin1, unicode),
            {<<Acc/binary, Bin/binary>>, Size0+Limit, 0, B2};
        Sz ->
            Bin = unicode:characters_to_binary(Bin0, latin1, unicode),
            {<<Acc/binary, Bin/binary>>, Size0+Sz, Limit-Sz, []}
    end;
limit_iolist_to_bin(Bin0, Limit, unicode, Size0, Acc)
  when is_binary(Bin0) ->
    try string:length(Bin0) of
        Sz when Sz > Limit ->
            B1 = string:slice(Bin0, 0, Limit),
            Skip = byte_size(Bin0) - byte_size(B1),
            <<_:Skip/binary, B2/binary>> = Bin0,
            {<<Acc/binary, B1/binary>>, Size0+Limit, 0, B2};
        Sz ->
            {<<Acc/binary, Bin0/binary>>, Size0+Sz, Limit-Sz, []}
    catch _:_ ->  %% We allow latin1 as binary strings, so try that
            limit_iolist_to_bin(Bin0, Limit, latin1, Size0, Acc)
    end;
limit_iolist_to_bin(CPs, Limit, unicode, Size, Acc) ->
    case string:next_grapheme(CPs) of
        {error, <<C,Cs1/binary>>} ->
            %% This is how ~ts handles Latin1 binaries with option
            %% chars_limit.
            limit_iolist_to_bin(Cs1, Limit-1, unicode, Size+1, <<Acc/binary, C/utf8>>);
        {error, [C|Cs1]} -> % not all versions of module string return this
            limit_iolist_to_bin(Cs1, Limit-1, unicode, Size+1, <<Acc/binary, C/utf8>>);
        [] ->
            {Acc, Size, Limit, []};
        [GC|Cs1] when is_integer(GC) ->
            limit_iolist_to_bin(Cs1, Limit-1, unicode, Size+1, <<Acc/binary, GC/utf8>>);
        [GC|Cs1] ->
            Utf8 = unicode:characters_to_binary(GC),
            limit_iolist_to_bin(Cs1, Limit-1, unicode, Size+1, <<Acc/binary, Utf8/binary>>)
    end;
limit_iolist_to_bin([Deep|Cs], Limit0, Enc, Size0, Acc0) ->
    {Acc, Sz, L, Cont} = limit_iolist_to_bin(Deep, Limit0, Enc, Size0, Acc0),
    case string:is_empty(Cont) of
        true ->
            limit_iolist_to_bin(Cs, L, Enc, Sz, Acc);
        false ->
            limit_iolist_to_bin([Cont|Cs], L, Enc, Sz, Acc)
    end;
limit_iolist_to_bin([], Limit, _Enc, Size, Acc) ->
    {Acc, Size, Limit, []}.

limit_field(F, CharsLimit) when CharsLimit < 0; F =:= none ->
    F;
limit_field(F, CharsLimit) ->
    max(3, min(F, CharsLimit)).

%% string(String, Field, Adjust, Precision, PadChar)

string(S, none, _Adj, none, _Pad, _Enc) ->
    S;
string(S, F, Adj, none, Pad, Enc) ->
    string_field(S, F, Adj, io_lib:chars_length(S), Pad, Enc);
string(S, none, _Adj, P, Pad, Enc) ->
    string_field(S, P, left, io_lib:chars_length(S), Pad, Enc);
string(S, F, Adj, P, Pad, Enc) when F >= P ->
    N = io_lib:chars_length(S),
    if F > P ->
	    if N > P ->
		    adjust(flat_trunc(S, P, Enc), chars(Pad, F-P), Adj);
	       N < P ->
		    adjust([S|chars(Pad, P-N)], chars(Pad, F-P), Adj);
	       true -> % N == P
		    adjust(S, chars(Pad, F-P), Adj)
	    end;
       true -> % F == P
	    string_field(S, F, Adj, N, Pad, Enc)
    end.

string_field(S, F, _Adj, N, _Pad, Enc) when N > F ->
    flat_trunc(S, F, Enc);
string_field(S, F, Adj, N, Pad, _Enc) when N < F ->
    adjust(S, chars(Pad, F-N), Adj);
string_field(S, _, _, _, _, _) -> % N == F
    S.

string_bin(S, _, none, _Adj, none, _Pad, _Enc) ->
    {S, -1, -1};
string_bin(S, undefined, F, Adj, P, Pad, Enc) ->
    unicode = Enc, %% Assert size=-1 should only happen for unicode
    string_bin(S, string:length(S), F, Adj, P, Pad, Enc);
string_bin(S, Sz, F, Adj, none, Pad, Enc) ->
    string_field_bin(S, F, Adj, Sz, Pad, Enc);
string_bin(S, Sz, none, _Adj, P, Pad, Enc) ->
    string_field_bin(S, P, left, Sz, Pad, Enc);
string_bin(S0, Sz, F, Adj, P, Pad, Enc) when F >= P ->
    if F > P ->
	    if Sz > P ->
                    S = adjust(flat_trunc(S0, P, Enc), chars(Pad, F-P), Adj),
                    {S, F, -1};
	       Sz < P ->
		    S = adjust([S0|chars(Pad, P-Sz)], chars(Pad, F-P), Adj),
                    {S, F, -1};
	       true -> % N == P
		    S = adjust(S0, chars(Pad, F-P), Adj),
                    {S, Sz+(F-P), -1}
	    end;
       true -> % F == P
	    string_field_bin(S0, F, Adj, Sz, Pad, Enc)
    end.

string_field_bin(S0, F, _Adj, N, _Pad, Enc) when N > F ->
    S = flat_trunc(S0, F, Enc),
    {S, F, -1};
string_field_bin(S0, F, Adj, N, Pad, _Enc) when N < F ->
    S = adjust(S0, chars(Pad, F-N), Adj),
    {S, N+F-N, -1};
string_field_bin(S, _, _, N, _, _) -> % N == F
    {S, N, -1}.


%% unprefixed_integer(Int, Field, Adjust, Base, PadChar, Lowercase)
%% -> [Char].

unprefixed_integer(Int, F, Adj, Base, Pad, Lowercase)
  when Base >= 2, Base =< 1+$Z-$A+10 ->
    if Int < 0 ->
	    S = cond_lowercase(erlang:integer_to_list(-Int, Base), Lowercase),
	    term([$-|S], F, Adj, none, Pad, latin1);
       true ->
	    S = cond_lowercase(erlang:integer_to_list(Int, Base), Lowercase),
	    term(S, F, Adj, none, Pad, latin1)
    end.

%% prefixed_integer(Int, Field, Adjust, Base, PadChar, Prefix, Lowercase)
%% -> [Char].

prefixed_integer(Int, F, Adj, Base, Pad, Prefix, Lowercase)
  when Base >= 2, Base =< 1+$Z-$A+10 ->
    if Int < 0 ->
	    S = cond_lowercase(erlang:integer_to_list(-Int, Base), Lowercase),
	    term([$-,Prefix|S], F, Adj, none, Pad, latin1);
       true ->
	    S = cond_lowercase(erlang:integer_to_list(Int, Base), Lowercase),
	    term([Prefix|S], F, Adj, none, Pad, latin1)
    end.

%% char(Char, Field, Adjust, Precision, PadChar) -> chars().

char(C, none, _Adj, none, _Pad) -> [C];
char(C, F, _Adj, none, _Pad) -> chars(C, F);
char(C, none, _Adj, P, _Pad) -> chars(C, P);
char(C, F, Adj, P, Pad) when F >= P ->
    adjust(chars(C, P), chars(Pad, F - P), Adj).

%% newline(Field, Adjust, Precision, PadChar) -> [Char].

newline(none, _Adj, _P, _Pad) -> "\n";
newline(F, right, _P, _Pad) -> chars($\n, F).

%%
%% Utilities
%%

adjust(Data, [], _) -> Data;
adjust(Data, Pad, left) -> [Data|Pad];
adjust(Data, Pad, right) -> [Pad|Data].

%% Flatten and truncate a deep list to at most N elements.

flat_trunc(List, N, latin1) when is_list(List), is_integer(N), N >= 0 ->
    {S, _} = lists:split(N, lists:flatten(List)),
    S;
flat_trunc(Str, N, unicode) when is_integer(N), N >= 0 ->
    string:slice(Str, 0, N);
flat_trunc(Bin, N, latin1) when is_binary(Bin), is_integer(N), N >= 0 ->
    {B, _} = split_binary(Bin, N),
    B.

%% A deep version of lists:duplicate/2

chars(_C, 0) ->
    [];
chars(C, 1) ->
    [C];
chars(C, 2) ->
    [C,C];
chars(C, 3) ->
    [C,C,C];
chars(C, N) when is_integer(N), (N band 1) =:= 0 ->
    S = chars(C, N bsr 1),
    [S|S];
chars(C, N) when is_integer(N) ->
    S = chars(C, N bsr 1),
    [C,S|S].

%chars(C, N, Tail) ->
%    [chars(C, N)|Tail].

%% Lowercase conversion

cond_lowercase(String, true) ->
    lowercase(String);
cond_lowercase(String,false) ->
    String.

lowercase([H|T]) when is_integer(H), H >= $A, H =< $Z ->
    [(H-$A+$a)|lowercase(T)];
lowercase([H|T]) ->
    [H|lowercase(T)];
lowercase([]) ->
    [].

%% Make sure T does not change sign.
sub(T, _) when T < 0 -> T;
sub(T, E) when T >= E -> T - E;
sub(_, _) -> 0.

get_option(Key, TupleList, Default) ->
    case lists:keyfind(Key, 1, TupleList) of
	false -> Default;
	{Key, Value} -> Value;
	_ -> Default
    end.
