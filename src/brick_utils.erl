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

-module(brick_utils).

%% ====================================================================
%% API functions
%% ====================================================================
-export([get_config/1, get_config/2]).
-export([version/0]).
-export([get_prop/2, get_prop/3]).

get_config(Param) -> application:get_env(brick, Param).

get_config(Param, Config) when is_list(Config) ->
  case lists:keyfind(Param, 1, Config) of
    {_, Value} -> {ok, Value};
    false -> undefined
  end;
get_config(Param1, Param2) ->
  {ok, Config} = get_config(Param1),
  get_config(Param2, Config).

version() ->
  {ok, Version} = application:get_key(brick, vsn),
  atom_to_binary(Version, utf8).

get_prop(Key, Props) ->
  case lists:keyfind(Key, 1, Props) of
    {_, Value} -> {ok, Value};
    false -> undefined
  end.

get_prop(Key, Props, Default) ->
  case lists:keyfind(Key, 1, Props) of
    {_, Value} -> Value;
    false -> Default
  end.

%% ====================================================================
%% Internal functions
%% ====================================================================

