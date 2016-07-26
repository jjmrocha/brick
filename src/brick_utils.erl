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
-export([version/0, cluster_name/0]).
-export([get_value/2, get_value/3]).

version() ->
	{ok, Version} = application:get_key(brick, vsn),
	list_to_binary(Version).

cluster_name() ->	
	Value = brick_config:get_env(cluster_name),
	atom_to_binary(Value, utf8).

get_value(Key, Props) ->
	get_value(Key, Props, undefined).

get_value(Key, Props, Default) ->
	case lists:keyfind(Key, 1, Props) of
		{_, Value} -> Value;
		false -> Default
	end.

%% ====================================================================
%% Internal functions
%% ====================================================================

