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
-export([multicast/3]).
-export([call/2, call/3]).
-export([reply/2]).
-export([whereis_name/1, register_name/2, unregister_name/1]).

cast(Process, Msg) ->
	send(Process, ?BRICK_RPC_CAST(Msg)),
	ok.

multicast([], _Name, _Msg) -> ok;
multicast([Node|T], Name, Msg) ->
	{Name, Node} ! ?BRICK_RPC_CAST(Msg),
	multicast(T, Name, Msg).

call(Process, Msg) ->
	call(Process, Msg, 5000).

call(Process, Msg, Timeout) ->
	Pid = pid(Process),
	MRef = erlang:monitor(process, Pid),
	Pid ! ?BRICK_RPC_CALL(?BRICK_RPC_FROM(self(), MRef), Msg),
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

reply(?BRICK_RPC_FROM(Pid, Ref), Msg) ->
	Pid ! ?BRICK_RPC_REPLY(Ref, Msg),
	ok.

whereis_name(Pid) when is_pid(Pid) -> Pid;
whereis_name(Name) when is_atom(Name) -> whereis(Name);
whereis_name({global, Name}) -> global:whereis_name(Name);
whereis_name(_) -> undefined.	

register_name(?BRICK_RPC_NONAME, _Pid) -> true;
register_name({local, Name}, Pid) -> 
	try register(Name, Pid)
	catch _:_ -> false
	end;
register_name({global, Name}, Pid) ->
	case global:register_name(Name, Pid) of
		yes -> true;
		no -> false
	end;
register_name(_Name, _Pid) -> exit(badname).

unregister_name(?BRICK_RPC_NONAME) -> true;
unregister_name({local, Name}) -> 
	try unregister(Name)
	catch _:_ -> false
	end;
unregister_name({global, Name}) ->
	global:unregister_name(Name),
	true;
unregister_name(_Name) -> exit(badname).

%% ====================================================================
%% Internal functions
%% ====================================================================

pid(Process) ->
	case whereis_name(Process) of
		undefined -> exit(noproc);
		Pid -> Pid
	end.

send({global, Name}, Msg) ->
	case global:whereis_name(Name) of
		undefined -> ok;
		Pid -> Pid ! Msg
	end;
send(Process, Msg) -> Process ! Msg.	