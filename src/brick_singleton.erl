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

-module(brick_singleton).

-behaviour(gen_server).

-define(SINGLETON(Name), {global, Name}).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ====================================================================
%% Callback functions
%% ====================================================================

-callback init(Args :: term()) ->
	{ok, State :: term()} | {ok, State :: term(), timeout() | hibernate} |
	{stop, Reason :: term()} | ignore.

-callback handle_call(Request :: term(), From :: {pid(), Tag :: term()}, State :: term()) ->
	{reply, Reply :: term(), NewState :: term()} |
	{reply, Reply :: term(), NewState :: term(), timeout() | hibernate} |
	{noreply, NewState :: term()} |
	{noreply, NewState :: term(), timeout() | hibernate} |
	{stop, Reason :: term(), Reply :: term(), NewState :: term()} |
	{stop, Reason :: term(), NewState :: term()}.

-callback handle_cast(Request :: term(), State :: term()) ->
	{noreply, NewState :: term()} |
	{noreply, NewState :: term(), timeout() | hibernate} |
	{stop, Reason :: term(), NewState :: term()}.

-callback handle_info(Info :: timeout | term(), State :: term()) ->
	{noreply, NewState :: term()} |
	{noreply, NewState :: term(), timeout() | hibernate} |
	{stop, Reason :: term(), NewState :: term()}.

-callback terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()), State :: term()) ->
	term().

-callback code_change(OldVsn :: (term() | {down, term()}), State :: term(), Extra :: term()) ->
	{ok, NewState :: term()} | {error, Reason :: term()}.

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/3, start/3]).
-export([call/2, call/3, cast/2, send/2]).

start_link(Name, Mod, Args) ->
	gen_server:start_link(?MODULE, [Name, Mod, Args], []).

start(Name, Mod, Args) ->
	gen_server:start(?MODULE, [Name, Mod, Args], []).

call(Name, Msg) -> call(Name, Msg, infinity).

call(Name, Msg, Timeout) ->
	gen_server:call(?SINGLETON(Name), Msg, Timeout).

cast(Name, Msg) ->
	gen_server:cast(?SINGLETON(Name), Msg).

send(Name, Msg) ->
	global:send(Name, Msg).

%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {name, mod, args, data, singleton=none}).

-define(update_state(State, Data), State#state{data=Data}).

%% init/1
init([Name, Mod, Args]) ->
	{ok, #state{name=Name, mod=Mod, args=Args}, 0}.

%% handle_call/3
handle_call(Request, From, State=#state{mod=Mod, data=Data, singleton=none}) ->
	Reply = Mod:handle_call(Request, From, Data),
	handle_reply(Reply, State);

handle_call(_Request, _From, State) ->
	{noreply, State, hibernate}.

%% handle_cast/2
handle_cast(Msg, State=#state{mod=Mod, data=Data, singleton=none}) ->
	Reply = Mod:handle_cast(Msg, Data),
	handle_reply(Reply, State);

handle_cast(_Msg, State) ->
	{noreply, State, hibernate}.

%% handle_info/2
handle_info(timeout, State=#state{name=Name, mod=Mod, args=Args, singleton=none}) ->
	case global:register_name(Name, self()) of
		yes ->
			case Mod:init(Args) of
				{ok, Data} -> {noreply, ?update_state(State, Data)};
				{ok, Data, hibernate} -> {noreply, ?update_state(State, Data), hibernate};
				{ok, Data, Timeout} -> {noreply, ?update_state(State, Data), Timeout};
				{stop, Reason} -> {stop, Reason, State};
				ignore -> {stop, ignore, State}
			end;
		no ->
			case global:whereis_name(Name) of
				undefined -> {noreply, State, 0};
				Pid -> 
					MRef = erlang:monitor(process, Pid),
					{noreply, State#state{singleton=MRef}, hibernate}
			end
	end;

handle_info({'DOWN', MRef, _, _, _}, State=#state{singleton=MRef}) ->
	{noreply, State#state{singleton=none}, 0};

handle_info(Info, State=#state{mod=Mod, data=Data, singleton=none}) ->
	Reply = Mod:handle_info(Info, Data),
	handle_reply(Reply, State);

handle_info(_Info, State) ->
	{noreply, State, hibernate}.

%% terminate/2
terminate(Reason, #state{mod=Mod, data=Data, singleton=none}) ->
	Mod:terminate(Reason, Data);

terminate(_Reason, #state{singleton=MRef}) ->
	erlang:demonitor(MRef),
	ok.

%% code_change/3
code_change(OldVsn, State=#state{mod=Mod, data=Data, singleton=none}, Extra) ->
	case Mod:code_change(OldVsn, Data, Extra) of
		{ok, NewData} -> {ok, ?update_state(State, NewData)};
		{error, Reason} -> {error, Reason}
	end;

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

handle_reply({reply, Reply, Data}, State) -> {reply, Reply, ?update_state(State, Data)};
handle_reply({reply, Reply, Data, hibernate}, State) -> {reply, Reply, ?update_state(State, Data), hibernate};
handle_reply({reply, Reply, Data, Timeout}, State) -> {reply, Reply, ?update_state(State, Data), Timeout};
handle_reply({noreply, Data}, State) -> {noreply, ?update_state(State, Data)};
handle_reply({noreply, Data, hibernate}, State) -> {noreply, ?update_state(State, Data), hibernate};
handle_reply({noreply, Data, Timeout}, State) -> {noreply, ?update_state(State, Data), Timeout};
handle_reply({stop, Reason , Reply, Data}, State) -> {stop, Reason , Reply, ?update_state(State, Data)};
handle_reply({stop, Reason, Data}, State) -> {stop, Reason, ?update_state(State, Data)}.
