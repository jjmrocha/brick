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

-module(brick_util).

%% ====================================================================
%% API functions
%% ====================================================================
-export([remove/2, common/2, not_in/2]).
-export([random_get/2]).
-export([shuffle/1]).
-export([whereis_name/1, register_name/2, unregister_name/1]).

remove([], List) -> List;
remove([H|T], List) -> remove(T, lists:delete(H, List)).

common(_List1, []) -> [];
common([], _List2) -> [];
common(List1, List2) -> 
	lists:filter(fun(Elem) -> 
				lists:member(Elem, List2) 
		end, List1).

not_in([], _List2) -> [];
not_in(List1, []) -> List1;
not_in(List1, List2) ->
	lists:filter(fun(E) -> 
				not lists:member(E, List2) 
		end, List1).

random_get([], _Count) -> [];
random_get(List, Count) -> random_get(shuffle(List), Count, []).

shuffle([]) -> [];
shuffle([Element]) -> [Element];
shuffle(List) -> [X || {_, X} <- lists:sort([{rand:uniform(), N} || N <- List])].

whereis_name(Pid) when is_pid(Pid) -> Pid;
whereis_name(Name) when is_atom(Name) -> whereis(Name);
whereis_name({via, Mod, Name}) -> Mod:whereis_name(Name);
whereis_name({global, Name}) -> global:whereis_name(Name);
whereis_name(_) -> undefined.	

register_name({local, Name}, Pid) -> 
	try register(Name, Pid)
	catch _:_ -> false
	end;
register_name({via, Mod, Name}, Pid) ->
	case Mod:register_name(Name, Pid) of
		yes -> true;
		no -> false
	end;
register_name({global, Name}, Pid) ->
	case global:register_name(Name, Pid) of
		yes -> true;
		no -> false
	end;
register_name(_Name, _Pid) -> exit(badname).

unregister_name({local, Name}) -> 
	try unregister(Name)
	catch _:_ -> false
	end;
unregister_name({via, Mod, Name}) ->
	Mod:unregister_name(Name),
	true;
unregister_name({global, Name}) ->
	global:unregister_name(Name),
	true;
unregister_name(_Name) -> exit(badname).

%% ====================================================================
%% Internal functions
%% ====================================================================

random_get(_All, 0, List) -> List;
random_get([], _Count, List) -> List;
random_get([H|T], Count, List) -> random_get(T, Count -1 , [H|List]).
