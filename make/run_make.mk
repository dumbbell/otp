# %CopyrightBegin%
#
# SPDX-License-Identifier: Apache-2.0
#
# Copyright Ericsson AB 1999-2025. All Rights Reserved.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 
# %CopyrightEnd%
#
# ----------------------------------------------------
# This make include file runs make recursively on the Makefile
# in the architecture dependent subdirectory.
#
# Typical use from Makefile:
#
#    include $(ERL_TOP)/make/run_make.mk
#
# ----------------------------------------------------

include $(ERL_TOP)/make/output.mk
include $(ERL_TOP)/make/target.mk

.PHONY: valgrind asan test

opt debug valgrind asan gcov gprof lcnt frmptr icount:
	$(make_verbose)$(MAKE) -f $(TARGET)/Makefile TYPE=$@

emu jit:
	$(make_verbose)$(MAKE) -f $(TARGET)/Makefile FLAVOR=$@

clean generate depend docs release release_spec release_docs release_docs_spec \
  tests release_tests release_tests_spec static_lib format format-check compdb:
	$(make_verbose)$(MAKE) -f $(TARGET)/Makefile $@

.NOTPARALLEL:
