%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2008-2020. All Rights Reserved.
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
%% This file is generated DO NOT EDIT

-module(wxCalendarEvent).
-include("wxe.hrl").
-export([getDate/1,getWeekDay/1]).

%% inherited exports
-export([getClientData/1,getExtraLong/1,getId/1,getInt/1,getSelection/1,getSkipped/1,
  getString/1,getTimestamp/1,isChecked/1,isCommandEvent/1,isSelection/1,
  parent_class/1,resumePropagation/2,setInt/2,setString/2,shouldPropagate/1,
  skip/1,skip/2,stopPropagation/1]).

-type wxCalendarEvent() :: wx:wx_object().
-include("wx.hrl").
-type wxCalendarEventType() :: 'calendar_sel_changed' | 'calendar_day_changed' | 'calendar_month_changed' | 'calendar_year_changed' | 'calendar_doubleclicked' | 'calendar_weekday_clicked'.
-export_type([wxCalendarEvent/0, wxCalendar/0, wxCalendarEventType/0]).
%% @hidden
parent_class(wxDateEvent) -> true;
parent_class(wxCommandEvent) -> true;
parent_class(wxEvent) -> true;
parent_class(_Class) -> erlang:error({badtype, ?MODULE}).

%% @doc See <a href="http://www.wxwidgets.org/manuals/2.8.12/wx_wxcalendarevent.html#wxcalendareventgetweekday">external documentation</a>.
%%<br /> Res = ?wxDateTime_Sun | ?wxDateTime_Mon | ?wxDateTime_Tue | ?wxDateTime_Wed | ?wxDateTime_Thu | ?wxDateTime_Fri | ?wxDateTime_Sat | ?wxDateTime_Inv_WeekDay
-spec getWeekDay(This) -> wx:wx_enum() when
	This::wxCalendarEvent().
getWeekDay(#wx_ref{type=ThisT}=This) ->
  ?CLASS(ThisT,wxCalendarEvent),
  wxe_util:queue_cmd(This,?get_env(),?wxCalendarEvent_GetWeekDay),
  wxe_util:rec(?wxCalendarEvent_GetWeekDay).

%% @doc See <a href="http://www.wxwidgets.org/manuals/2.8.12/wx_wxcalendarevent.html#wxcalendareventgetdate">external documentation</a>.
-spec getDate(This) -> wx:wx_datetime() when
	This::wxCalendarEvent().
getDate(#wx_ref{type=ThisT}=This) ->
  ?CLASS(ThisT,wxCalendarEvent),
  wxe_util:queue_cmd(This,?get_env(),?wxCalendarEvent_GetDate),
  wxe_util:rec(?wxCalendarEvent_GetDate).

 %% From wxDateEvent
 %% From wxCommandEvent
%% @hidden
setString(This,String) -> wxCommandEvent:setString(This,String).
%% @hidden
setInt(This,IntCommand) -> wxCommandEvent:setInt(This,IntCommand).
%% @hidden
isSelection(This) -> wxCommandEvent:isSelection(This).
%% @hidden
isChecked(This) -> wxCommandEvent:isChecked(This).
%% @hidden
getString(This) -> wxCommandEvent:getString(This).
%% @hidden
getSelection(This) -> wxCommandEvent:getSelection(This).
%% @hidden
getInt(This) -> wxCommandEvent:getInt(This).
%% @hidden
getExtraLong(This) -> wxCommandEvent:getExtraLong(This).
%% @hidden
getClientData(This) -> wxCommandEvent:getClientData(This).
 %% From wxEvent
%% @hidden
stopPropagation(This) -> wxEvent:stopPropagation(This).
%% @hidden
skip(This, Options) -> wxEvent:skip(This, Options).
%% @hidden
skip(This) -> wxEvent:skip(This).
%% @hidden
shouldPropagate(This) -> wxEvent:shouldPropagate(This).
%% @hidden
resumePropagation(This,PropagationLevel) -> wxEvent:resumePropagation(This,PropagationLevel).
%% @hidden
isCommandEvent(This) -> wxEvent:isCommandEvent(This).
%% @hidden
getTimestamp(This) -> wxEvent:getTimestamp(This).
%% @hidden
getSkipped(This) -> wxEvent:getSkipped(This).
%% @hidden
getId(This) -> wxEvent:getId(This).
