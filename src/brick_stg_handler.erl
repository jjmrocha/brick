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

-module(brick_stg_handler).

%% ====================================================================
%% API functions
%% ====================================================================

-callback init(Args :: list()) -> 
	{ok, State :: term()} | {stop, Reason :: term()}. 

-callback states(State :: term()) -> 
	{ok, StateList :: list(), NewState :: term()} | {stop, Reason :: term(), NewState :: term()}.

-callback read(Name :: atom(), State :: term()) -> 
	{ok, Value :: term(), Version :: integer(), NewState :: term()} | {not_found, NewState :: term()} | {stop, Reason :: term(), NewState :: term()}. 

-callback write(Name :: atom(), Value :: term(), Version :: integer(), State :: term()) -> 
	{ok, NewState :: term()} | {stop, Reason :: term(), NewState :: term()}.

-callback code_change(OldVsn :: Vsn | {down, Vsn}, State :: term(), Extra :: term()) -> 
	{ok, NewState :: term()} | {error, Reason :: term()}.

-callback terminate(State :: term()) -> 
	Any :: term().
