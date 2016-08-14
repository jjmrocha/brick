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

-module(brick_rpc).

-include("brick_rpc.hrl").

%% ====================================================================
%% API functions
%% ====================================================================
-export([cast/2]).
-export([call/2, call/3]).
-export([reply/2]).

cast(Pid, Msg) ->
	Pid ! ?BRICK_RPC_CAST(Msg),
	ok.

call(Pid, Msg) ->
	call(Pid, Msg, infinity).

call(Pid, Msg, Timeout) ->
    MRef = erlang:monitor(process, Pid),
    Pid ! ?BRICK_RPC_CALL(self(), MRef, Msg),
    receive
        ?BRICK_RPC_REPLY(MRef, Reply) ->
            erlang:demonitor(MRef, [flush]),
            Reply;
        {'DOWN', MRef, _, _, Reason} ->
            exit(Reason)
    after Timeout ->
            erlang:demonitor(MRef, [flush]),
            exit(timeout)
    end.

reply(?BRICK_RPC_FROM(From, Ref), Msg) ->
	From ! ?BRICK_RPC_REPLY(Ref, Msg),
	ok.

%% ====================================================================
%% Internal functions
%% ====================================================================


