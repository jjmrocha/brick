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

-module(brick_event).

-include("brick_event.hrl").

-define(HANDLER(Type, EventName, Susbcriber), {?MODULE, {Type, EventName, Susbcriber}}).

-behaviour(gen_event).

-export([init/1, handle_event/2, handle_call/2, handle_info/2, terminate/2, code_change/3]).
%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).
-export([subscribe/3, unsubscribe/3]).
-export([publish/3]).

start_link() ->
	gen_event:start_link({local, ?MODULE}).

subscribe(Type, EventName, Subscriber) ->
	gen_event:add_handler(?MODULE, ?HANDLER(Type, EventName, Subscriber), [Type, EventName, Subscriber]).

unsubscribe(Type, EventName, Subscriber) ->
	gen_event:delete_handler(?MODULE, ?HANDLER(Type, EventName, Subscriber), []).

publish(Type, EventName, Value) ->
	Event = #brick_event{name=EventName, value=Value},
	gen_event:notify(?MODULE, {Type, Event}).

%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {type, name, subscriber, ref}).

%% init/1
init([Type, EventName, Subscriber]) ->
	MonitorRef = erlang:monitor(process, Subscriber),
	{ok, #state{type=Type, name=EventName, subscriber=Subscriber, ref=MonitorRef}}.

%% handle_event/2
handle_event({Type, Event=#brick_event{name=EventName}}, State=#state{type=Type, name=EventName, subscriber=Subscriber}) ->
	Subscriber ! Event,
	{ok, State};

handle_event(_Event, State) ->
	{ok, State}.

%% handle_call/2
handle_call(_Request, State) ->
	{ok, ok, State}.

%% handle_info/2
handle_info({'DOWN', MonitorRef, _Type, _Object, _Info}, #state{ref=MonitorRef}) ->
	remove_handler;

handle_info(_Info, State) ->
	{ok, State}.

%% terminate/2
terminate(_Arg, #state{ref=MonitorRef}) ->
	erlang:demonitor(MonitorRef),
	ok.

%% code_change/3
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================



