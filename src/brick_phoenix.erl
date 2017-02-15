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

-include("brick_global.hrl").

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
%% ====================================================================
%% Callback functions
%% ====================================================================

-callback init(Args :: term()) ->
	{ok, ProcessState :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp()} |
	{ok, ProcessState :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp(), timeout() | hibernate} |
	{stop, Reason :: term()} |
	ignore.

-callback handle_call(Request :: term(), From :: {pid(), Tag :: term()}, ProcessState :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp()) ->
	{reply, Reply :: term(), NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp()} |
	{reply, Reply :: term(), NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp(), timeout() | hibernate} |
	{reply, Reply :: term(), NewProcessState :: term()} |
	{reply, Reply :: term(), NewProcessState :: term(), timeout() | hibernate} |
	{noreply, NewProcessState :: term()} |
	{noreply, NewProcessState :: term(), timeout() | hibernate} |
	{noreply, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp()} |
	{noreply, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp(), timeout() | hibernate} |
	{stop, Reason :: term(), Reply :: term(), NewProcessState :: term()} |
	{stop, Reason :: term(), NewProcessState :: term()}.

-callback handle_cast(Request :: term(), ProcessState :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp()) ->
	{noreply, NewProcessState :: term()} |
	{noreply, NewProcessState :: term(), timeout() | hibernate} |
	{noreply, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp()} |
	{noreply, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp(), timeout() | hibernate} |
	{stop, Reason :: term(), NewProcessState :: term()}.

-callback handle_info(Info :: timeout | term(), ProcessState :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp()) ->
	{noreply, NewProcessState :: term()} |
	{noreply, NewProcessState :: term(), timeout() | hibernate} |
	{noreply, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp()} |
	{noreply, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp(), timeout() | hibernate} |
	{stop, Reason :: term(), NewProcessState :: term()}.

-callback terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()), ProcessState :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp()) ->
	term().

-callback code_change(OldVsn :: (term() | {down, term()}), ProcessState :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp(), Extra :: term()) ->
	{ok, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp()} |
	{error, Reason :: term()}.

-callback reborn(Args :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp()) ->
	{ok, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp()} |
	{ok, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp(), timeout() | hibernate} |
	{stop, Reason :: term()}.

-callback handle_state_update(ProcessState :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp()) ->
	{ok, NewProcessState :: term()} |
	{stop, Reason :: term()}.

-optional_callbacks([handle_state_update/3]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/3, start/3]).
-export([call_master/2, call_master/3, call_local/2, call_local/3, cast/2, send/2]).

start_link(Name, Mod, Args) ->
	validate_name(Name),
	LocalName = local_name(Name),
	gen_server:start_link({local, LocalName}, ?MODULE, [Name, Mod, Args], []).

start(Name, Mod, Args) ->
	validate_name(Name),
	LocalName = local_name(Name),
	gen_server:start({local, LocalName}, ?MODULE, [Name, Mod, Args], []).

call_master(Name, Msg) ->
	gen_server:call(Name, Msg).

call_master(Name, Msg, Timeout) ->
	gen_server:call(Name, Msg, Timeout).

call_local(Name, Msg) when is_atom(Name) ->
	gen_server:call(Name, Msg).
call_local(Name, Msg) ->
	call_local(local_name(Name), Msg).

call_local(Name, Msg, Timeout) when is_atom(Name) ->
	gen_server:call(Name, Msg, Timeout).
call_local(Name, Msg, Timeout) ->
	call_local(local_name(Name), Msg, Timeout).

cast(Name, Msg) ->
	gen_server:cast(Name, Msg).

send(Name, Msg) ->
	brick_util:send(Name, Msg).

%% ====================================================================
%% Behavioural functions
%% ====================================================================

-define(ROLE_MASTER, $m).
-define(ROLE_SLAVE, $s).
-define(NO_ROLE, $i).

-define(STATUS_UPDATE_QUEUE, '$brick_phoenix_async_queue').
-define(UPDATE_MSG(Data, Timestamp), {'$brick_phoenix_update_data', Data, Timestamp}).
-define(WELCOME_MSG(From), {'$brick_phoenix_welcome', From}).

-record(state, {name,
		mod,
		args,
		pdata,
		cdata,
		ts=none,
		role=?NO_ROLE,
		slaves=[],
		monitors=dict:new(),
		run_update_handler}).

%% init/1
init([Name, Mod, Args]) ->
	State = #state{name=Name,
		       mod=Mod,
		       args=Args,
		       run_update_handler=erlang:function_exported(Mod, handle_state_update, 1)},
	Timeout = timeout(Name),
	{ok, State, Timeout}.

%% handle_call/3
handle_call(Request, From, State=#state{mod=Mod, pdata=Data, ts=TS, role=?ROLE_MASTER}) ->
	Reply = Mod:handle_call(Request, From, Data, TS),
	handle_reply(Reply, State);

handle_call(Request, From, State=#state{mod=Mod, pdata=Data, ts=TS, role=?ROLE_SLAVE}) ->
	Reply = Mod:handle_call(Request, From, Data, TS),
	handle_reply(Reply, State);

handle_call(_Request, _From, State) ->
	{noreply, State, hibernate}.

%% handle_cast/2
handle_cast(?WELCOME_MSG(From), State=#state{pdata=Data, ts=TS, role=?ROLE_MASTER}) ->
	gen_server:cast(From, ?UPDATE_MSG(Data, TS)),
	State1 = #state{slaves=SlaveList} = monitor_pid(State, From),
	SlaveList1 = brick_util:iif(lists:member(From, SlaveList), SlaveList, [From|SlaveList]),
	{noreply, State1#state{slaves=SlaveList1}};

handle_cast(Msg, State=#state{mod=Mod, pdata=Data, ts=TS, role=?ROLE_MASTER}) ->
	Reply = Mod:handle_cast(Msg, Data, TS),
	handle_reply(Reply, State);

handle_cast(?UPDATE_MSG(Data, TS), State=#state{mod=Mod, role=?ROLE_SLAVE, run_update_handler=true}) ->
	brick_hlc:update(TS),
	case Mod:handle_state_update(Data, TS) of
		{ok, NewData, NewTS} -> {noreply, State#state{pdata=NewData, ts=NewTS}};
		{ok, NewData, NewTS, hibernate} -> {noreply, State#state{pdata=NewData, ts=NewTS}, hibernate};
		{ok, NewData, NewTS, Timeout} -> {noreply, State#state{pdata=NewData, ts=NewTS}, Timeout};
		{stop, Reason} -> {stop, Reason, State}
	end;

handle_cast(?UPDATE_MSG(Data, TS), State=#state{role=?ROLE_SLAVE}) ->
	brick_hlc:update(TS),
	{noreply, State#state{data=Data, ts=TS}};

handle_cast(_Msg, State=#state{status=?ROLE_SLAVE}) ->
	{noreply, State};

handle_cast(_Msg, State) ->
	{noreply, State, hibernate}.

%% handle_info/2
handle_info(Info = {'DOWN', MRef, _, _, _}, State=#state{mod=Mod, pdata=Data, ts=TS, role=?ROLE_MASTER}) ->
	case remove_ref(State, MRef) of
		ignore ->
			Reply = Mod:handle_info(Info, Data, TS),
			handle_reply(Reply, State);
		{Pid, State1} ->
			SlaveList = lists:delete(Pid, State1#state.slaves),
			{noreply, State1#state{slaves=SlaveList}}
	end;

handle_info(?RESOLVE_REQUEST(From, Ref), State=#state{ts=TS}) ->
	From ! ?RESOLVE_RESPONSE(Ref, TS),
	{noreply, State};

handle_info(Info, State=#state{mod=Mod, pdata=Data, ts=TS, role=?ROLE_MASTER}) ->
	Reply = Mod:handle_info(Info, Data, TS),
	handle_reply(Reply, State);

handle_info({'DOWN', MRef, _, _, _}, State=#state{role=?ROLE_SLAVE}) ->
	case remove_ref(State, MRef) of
		ignore -> {noreply, State};
		{_, State1} -> {noreply, State1, 0}
	end;

handle_info(timeout, State=#state{name=Name, mod=Mod, args=Args, role=Status, pdata=Data, ts=TS}) ->
	case {brick_util:register_name(Name, self(), fun brick_global:resolver/3), Status} of
		{true, ?NO_ROLE} ->
			case Mod:init(Args) of
				{ok, NewData, NewTS} -> {noreply, update_state(State#state{status=?ROLE_MASTER}, NewData, NewTS)};
				{ok, NewData, NewTS, hibernate} -> {noreply, update_state(State#state{status=?ROLE_MASTER}, NewData, NewTS), hibernate};
				{ok, NewData, NewTS, Timeout} -> {noreply, update_state(State#state{status=?ROLE_MASTER}, NewData, NewTS), Timeout};
				{stop, Reason} -> {stop, Reason, State};
				ignore -> {stop, ignore, State};
				Other -> Other
			end;
		{true, _} ->
			case Mod:reborn(Data, TS) of
				{ok, NewData, NewTS} -> {noreply, update_state(State#state{role=?ROLE_MASTER}, NewData, NewTS)};
				{ok, NewData, NewTS, hibernate} -> {noreply, update_state(State#state{role=?ROLE_MASTER}, NewData, NewTS), hibernate};
				{ok, NewData, NewTS, Timeout} -> {noreply, update_state(State#state{role=?ROLE_MASTER}, NewData, NewTS), Timeout};
				{stop, Reason} -> {stop, Reason, State};
				Other -> Other
			end;
		{false, _} ->
			case brick_util:whereis_name(Name) of
				undefined -> {noreply, State, 0};
				Pid ->
					gen_server:cast(Pid, ?WELCOME_MSG(self())),
					{noreply, monitor_pid(State#state{role=?ROLE_SLAVE}, Pid)}
			end
	end;

handle_info(_Info, State) ->
	{noreply, State, hibernate}.

%% terminate/2
terminate(Reason, State=#state{name=Name, mod=Mod, pdata=Data, ts=TS, role=?ROLE_MASTER}) ->
	demonitor_pids(State),
	Mod:terminate(Reason, Data, TS),
	brick_util:unregister_name(Name);

terminate(_Reason, State) ->
	demonitor_pids(State).

%% code_change/3
code_change(OldVsn, State=#state{mod=Mod, pdata=Data, ts=TS, role=?ROLE_MASTER}, Extra) ->
	case Mod:code_change(OldVsn, Data, TS, Extra) of
		{ok, NewData, NewTS} -> {ok, update_state(State, NewData, NewTS)};
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

local_name({global, Name}) -> Name;
local_name({via, brick_global, Name}) -> Name;
local_name(Name) when is_atom(Name) -> Name;
local_name(Name) -> exit({invalid_name, Name}).

timeout({global, _}) -> timeout_by_custer_size(nodes());
timeout({via, brick_global, brick_state}) -> timeout_by_custer_size(nodes());
timeout({via, brick_global, _}) -> timeout_by_custer_size(brick_cluster:online_nodes()).

timeout_by_custer_size([]) -> 0;
timeout_by_custer_size([_]) -> 0;
timeout_by_custer_size(_) -> 1000.

handle_reply({reply, Reply, Data, TS}, State) -> {reply, Reply, update_state(State, Data, TS)};
handle_reply({reply, Reply, Data, TS, hibernate}, State) -> {reply, Reply, update_state(State, Data, TS), hibernate};
handle_reply({reply, Reply, Data, TS, Timeout}, State) -> {reply, Reply, update_state(State, Data, TS), Timeout};
handle_reply({noreply, Data, TS}, State) -> {noreply, update_state(State, Data, TS)};
handle_reply({noreply, Data, TS, hibernate}, State) -> {noreply, update_state(State, Data, TS), hibernate};
handle_reply({noreply, Data, TS, Timeout}, State) -> {noreply, update_state(State, Data, TS), Timeout};
handle_reply({stop, Reason , Reply, Data, TS}, State) -> {stop, Reason , Reply, update_state(State, Data, TS)};
handle_reply({stop, Reason, Data, TS}, State) -> {stop, Reason, update_state(State, Data, TS)};
handle_reply(Other, _State) -> Other.

update_state(State=#state{role=?ROLE_MASTER}, Data, TS) when State#state.data =/= Data orelse State#state.ts =/= TS ->
	uppdate_slaves(State, Data, TS),
	State#state{data=Data, ts=TS};
update_state(State, _Data, _TS) -> State.

uppdate_slaves(#state{slaves=[]}, _Data, _TS) -> ok;
uppdate_slaves(State = #state{slaves=Pids}, Data, TS) when State#state.ts =/= TS ->
	brick_async:run(?STATUS_UPDATE_QUEUE, fun() ->
			publish(Pids, Data, TS)
		end);
uppdate_slaves(_State, _Data, _TS) -> ok.

publish([], _Data, _TS) -> ok;
publish([Pid|T], Data, TS) ->
	gen_server:cast(Pid, ?UPDATE_MSG(Data, TS)),
	publish(T, Data, TS).

monitor_pid(State=#state{mon=Mon}, Pid) ->
	Search = lists:filter(fun({_, P}) when P =:= Pid -> true;
				(_) -> false end, dict:to_list(Mon)),
	Mon1 = case Search of
		[] ->
			MRef = erlang:monitor(process, Pid),
			dict:store(MRef, Pid, Mon);
		_ -> Mon
	end,
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
