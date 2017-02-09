%%
%% Copyright 2016-17 Joaquim Rocha <jrocha@gmailbox.org>
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

-module(brick_phoenix).

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
%% ====================================================================
%% Callback functions
%% ====================================================================

-callback init(Args :: term()) ->
	{ok, State :: term()} |
	{ok, State :: term(), timeout() | hibernate} |
	{stop, Reason :: term()} |
	ignore.

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
	{ok, NewState :: term()} |
	{error, Reason :: term()}.

-callback reborn(State :: term()) ->
	{ok, NewState :: term()} |
	{ok, NewState :: term(), timeout() | hibernate} |
	{stop, Reason :: term()}.

-callback handle_state_update(State :: term()) ->
	{ok, NewState :: term()} |
	{ok, NewState :: term(), timeout() | hibernate} |
	{stop, Reason :: term()}.

-optional_callbacks([handle_state_update/1]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/3, start/3]).
-export([call/2, call/3, cast/2, send/2]).

start_link(Name, Mod, Args) ->
	validate_name(Name),
	gen_server:start_link(?MODULE, [Name, Mod, Args], []).

start(Name, Mod, Args) ->
	validate_name(Name),
	gen_server:start(?MODULE, [Name, Mod, Args], []).

call(Name, Msg) ->
	gen_server:call(Name, Msg).

call(Name, Msg, Timeout) ->
	gen_server:call(Name, Msg, Timeout).

cast(Name, Msg) ->
	gen_server:cast(Name, Msg).

send(Name, Msg) ->
	brick_util:send(Name, Msg).

%% ====================================================================
%% Behavioural functions
%% ====================================================================

-define(STATUS_MASTER, $m).
-define(STATUS_SLAVE, $s).
-define(STATUS_IDLE, $i).

-define(STATUS_UPDATE_QUEUE, '$brick_phoenix_async_queue').
-define(UPDATE_MSG(Data, Timestamp), {'$brick_phoenix_update_data', Data, Timestamp}).
-define(WELCOME_MSG(Pid, Timestamp), {'$brick_phoenix_welcome', Pid, Timestamp}).

-record(state, {name, mod, args, data, status=?STATUS_IDLE, slave_list=[], mon=dict:new(), update_handler}).

%% init/1
init([Name, Mod, Args]) ->
	Timeout = timeout(Name),
	UseUpdateHandler = erlang:function_exported(Mod, handle_state_update, 1),
	{ok, #state{name=Name, mod=Mod, args=Args, update_handler=UseUpdateHandler}, Timeout}.

%% handle_call/3
handle_call(Request, From, State=#state{mod=Mod, data=Data, status=?STATUS_MASTER}) ->
	Reply = Mod:handle_call(Request, From, Data),
	handle_reply(Reply, State);

handle_call(_Request, _From, State=#state{status=?STATUS_SLAVE}) ->
	{noreply, State};

handle_call(_Request, _From, State) ->
	{noreply, State, hibernate}.

%% handle_cast/2
handle_cast(?WELCOME_MSG(Pid, Timestamp), State=#state{data=Data, status=?STATUS_MASTER}) ->
	NewTimestamp = brick_hlc:update(Timestamp),
	gen_server:cast(Pid, ?UPDATE_MSG(Data, NewTimestamp)),
	State1 = #state{slave_list=SlaveList} = monitor_pid(State, Pid),
	SlaveList1 = brick_util:iif(lists:member(Pid, SlaveList), SlaveList, [Pid|SlaveList]),
	{noreply, State1#state{slave_list=SlaveList1}};

handle_cast(Msg, State=#state{mod=Mod, data=Data, status=?STATUS_MASTER}) ->
	Reply = Mod:handle_cast(Msg, Data),
	handle_reply(Reply, State);

handle_cast(?UPDATE_MSG(Data, Timestamp), State=#state{mod=Mod, status=?STATUS_SLAVE, update_handler=true}) ->
	brick_hlc:update(Timestamp),
	case Mod:handle_state_update(Data) of
		{ok, NewData} -> {noreply, State#state{data=NewData}};
		{ok, NewData, hibernate} -> {noreply, State#state{data=NewData}, hibernate};
		{ok, NewData, Timeout} -> {noreply, State#state{data=NewData}, Timeout};
		{stop, Reason} -> {stop, Reason, State}
	end;

handle_cast(?UPDATE_MSG(Data, Timestamp), State=#state{status=?STATUS_SLAVE}) ->
	brick_hlc:update(Timestamp),
	{noreply, State#state{data=Data}};

handle_cast(_Msg, State=#state{status=?STATUS_SLAVE}) ->
	{noreply, State};

handle_cast(_Msg, State) ->
	{noreply, State, hibernate}.

%% handle_info/2
handle_info(Info = {'DOWN', MRef, _, _, _}, State=#state{mod=Mod, data=Data, status=?STATUS_MASTER}) ->
	case remove_ref(State, MRef) of
		ignore ->
			Reply = Mod:handle_info(Info, Data),
			handle_reply(Reply, State);
		{Pid, State1} ->
			SlaveList = lists:delete(Pid, State1#state.slave_list),
			{noreply, State1#state{slave_list=SlaveList}}
	end;

handle_info(Info, State=#state{mod=Mod, data=Data, status=?STATUS_MASTER}) ->
	Reply = Mod:handle_info(Info, Data),
	handle_reply(Reply, State);

handle_info({'DOWN', MRef, _, _, _}, State=#state{status=?STATUS_SLAVE}) ->
	case remove_ref(State, MRef) of
		ignore -> {noreply, State};
		{_, State1} -> {noreply, State1, 0}
	end;

handle_info(timeout, State=#state{name=Name, mod=Mod, args=Args, status=Status, data=Data}) ->
	case {brick_util:register_name(Name, self(), fun brick_global:resolver/3), Status} of
		{true, ?STATUS_IDLE} ->
			case Mod:init(Args) of
				{ok, NewData} -> {noreply, update_state(State#state{status=?STATUS_MASTER}, NewData)};
				{ok, NewData, hibernate} -> {noreply, update_state(State#state{status=?STATUS_MASTER}, NewData), hibernate};
				{ok, NewData, Timeout} -> {noreply, update_state(State#state{status=?STATUS_MASTER}, NewData), Timeout};
				{stop, Reason} -> {stop, Reason, State};
				ignore -> {stop, ignore, State};
				Other -> Other
			end;
		{true, _} ->
			case Mod:reborn(Data) of
				{ok, NewData} -> {noreply, update_state(State#state{status=?STATUS_MASTER}, NewData)};
				{ok, NewData, hibernate} -> {noreply, update_state(State#state{status=?STATUS_MASTER}, NewData), hibernate};
				{ok, NewData, Timeout} -> {noreply, update_state(State#state{status=?STATUS_MASTER}, NewData), Timeout};
				{stop, Reason} -> {stop, Reason, State};
				Other -> Other
			end;
		{false, _} ->
			case brick_util:whereis_name(Name) of
				undefined -> {noreply, State, 0};
				Pid ->
					gen_server:cast(Pid, ?WELCOME_MSG(self(), brick_hlc:timestamp())),
					{noreply, monitor_pid(State#state{status=?STATUS_SLAVE}, Pid)}
			end
	end;

handle_info(_Info, State) ->
	{noreply, State, hibernate}.

%% terminate/2
terminate(Reason, State=#state{name=Name, mod=Mod, data=Data, status=?STATUS_MASTER}) ->
	demonitor_pids(State),
	brick_util:unregister_name(Name),
	Mod:terminate(Reason, Data);

terminate(_Reason, State) ->
	demonitor_pids(State).

%% code_change/3
code_change(OldVsn, State=#state{mod=Mod, data=Data, status=?STATUS_MASTER}, Extra) ->
	case Mod:code_change(OldVsn, Data, Extra) of
		{ok, NewData} -> {ok, update_state(State, NewData)};
		{error, Reason} -> {error, Reason}
	end;

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

validate_name({global, _}) -> ok;
validate_name({via, brick_global, _}) -> ok;
validate_name(Name) -> exit({invalid_name, Name}).

timeout({global, _}) -> timeout_by_custer_size(nodes());
timeout({via, brick_global, _}) -> timeout_by_custer_size(brick_cluster:online_nodes()).

timeout_by_custer_size([]) -> 0;
timeout_by_custer_size([_]) -> 0;
timeout_by_custer_size(_) -> 1000.

handle_reply({reply, Reply, Data}, State) -> {reply, Reply, update_state(State, Data)};
handle_reply({reply, Reply, Data, hibernate}, State) -> {reply, Reply, update_state(State, Data), hibernate};
handle_reply({reply, Reply, Data, Timeout}, State) -> {reply, Reply, update_state(State, Data), Timeout};
handle_reply({noreply, Data}, State) -> {noreply, update_state(State, Data)};
handle_reply({noreply, Data, hibernate}, State) -> {noreply, update_state(State, Data), hibernate};
handle_reply({noreply, Data, Timeout}, State) -> {noreply, update_state(State, Data), Timeout};
handle_reply({stop, Reason , Reply, Data}, State) -> {stop, Reason , Reply, update_state(State, Data)};
handle_reply({stop, Reason, Data}, State) -> {stop, Reason, update_state(State, Data)};
handle_reply(Other, _State) -> Other.

update_state(State, Data) when State#state.data =/= Data ->
	brick_async:run(?STATUS_UPDATE_QUEUE, fun() ->
			publish(State#state.slave_list, Data)
		end),
	State#state{data=Data};
update_state(State, _Data) -> State.

publish([], _Data) -> ok;
publish([Pid|T], Data) ->
	gen_server:cast(Pid, ?UPDATE_MSG(Data, brick_hlc:timestamp())),
	publish(T, Data).

monitor_pid(State=#state{mon=Mon}, Pid) ->
	Search = lists:filter(fun({_, P}) when P =:= Pid -> true;
				(_) -> false end, dict:to_list(Mon)),
	MRef = case Search of
		[] -> erlang:monitor(process, Pid);
		[{Ref, _}] -> Ref
	end,
	Mon1 = dict:store(MRef, Pid, Mon),
	State#state{mon=Mon1}.

demonitor_pids(#state{mon=Mon}) ->
	lists:foreach(fun(MRef) ->
				erlang:demonitor(MRef)
		end, dict:fetch_keys(Mon)).

remove_ref(State=#state{mon=Mon}, MRef) ->
	case dict:find(MRef, Mon) of
		error -> ignore;
		{ok, Pid} ->
			Mon1 = dict:erase(MRef, Mon),
			{Pid, State#state{mon=Mon1}}
	end.
