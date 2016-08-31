%%
%% Copyright 2016 Joaquim Rocha <jrocha@gmailbox.org>
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%

-module(brick_config).

%% ====================================================================
%% API functions
%% ====================================================================
-export([peek_env/1]).
-export([get_env/1, get_env/2]).
-export([set_env/2]).

peek_env(Param) -> application:get_env(brick, Param).

get_env(Param) -> 
	{ok, Value} = application:get_env(brick, Param),
	Value.

get_env(Param1, Param2) ->
	Config = get_env(Param1),
	get_value(Param2, Config).

set_env(Param, Value) ->
	application:set_env(brick, Param, Value).

%% ====================================================================
%% Internal functions
%% ====================================================================

get_value(Param, Config) ->
	{_, Value} = lists:keyfind(Param, 1, Config),
	Value.
