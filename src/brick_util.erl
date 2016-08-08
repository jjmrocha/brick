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
-export([remove/2]).
-export([random_get/2]).
-export([shuffle/1]).

remove([], List) -> List;
remove([H|T], List) -> remove(T, lists:delete(H, List)).

random_get([], _Count) -> [];
random_get(List, Count) -> random_get(shuffle(List), Count, []).
	
shuffle(List) -> [X || {_, X} <- lists:sort([{random:uniform(), N} || N <- List])].

%% ====================================================================
%% Internal functions
%% ====================================================================

random_get(_All, 0, List) -> List;
random_get([], _Count, List) -> List;
random_get([H|T], Count, List) -> random_get(T, Count -1 , [H|List]).
