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

-module(brick_pool).

-behaviour(gen_server).

-define(EXIT_REASON(Reason), {'$brick_pool_exit', Reason}).
-define(STOP_REASON(Reason), {'$brick_pool_stop', Reason}).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ====================================================================
%% Callback functions
%% ====================================================================

-callback init(Args :: term()) ->
	{ok, State :: term()} |
	{stop, Reason :: term()} | 
	ignore.

-callback handle_call(Request :: term(), From :: {pid(), Tag :: term()}, State :: term()) ->
	{reply, Reply :: term()} |
	noreply |
	{stop, Reason :: term(), Reply :: term()} |
	{stop, Reason :: term()}.

-callback handle_cast(Request :: term(), State :: term()) ->
	noreply |
	{stop, Reason :: term()}.

-callback handle_info(Info :: timeout | term(), State :: term()) ->
	noreply |
	{stop, Reason :: term()}.

-callback terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()), State :: term()) ->
	term().

-callback code_change(OldVsn :: (term() | {down, term()}), State :: term(), Extra :: term()) ->
	{ok, NewState :: term()} | {error, Reason :: term()}.

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/3, start_link/4]).
-export([start/3, start/4]).
-export([stop/1, stop/3]).
-export([call/2, call/3, cast/2]).

start_link(Mod, Args, Options) ->
	gen_server:start_link(?MODULE, [Mod, Args, Options], []).

start_link(Name, Mod, Args, Options) ->
	gen_server:start_link(Name, ?MODULE, [Mod, Args, Options], []).

start(Mod, Args, Options) ->
	gen_server:start(?MODULE, [Mod, Args, Options], []).

start(Name, Mod, Args, Options) ->
	gen_server:start(Name, ?MODULE, [Mod, Args, Options], []).

stop(Process) -> 
	gen_server:stop(Process).

stop(Process, Reason, Timeout) -> 
	gen_server:stop(Process, Reason, Timeout).

call(Process, Msg) -> 
	gen_server:call(Process, Msg).

call(Process, Msg, Timeout) ->
	gen_server:call(Process, Msg, Timeout).

cast(Process, Msg) ->
	gen_server:cast(Process, Msg).

%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {queue, mod, data}).

%% init/1
init([Mod, Args, Options]) ->
	case Mod:init(Args) of
		{ok, Data} ->
			process_flag(trap_exit, true),
			{ok, Pid} = brick_queue:start_link(Options),
			{ok, #state{queue=Pid, mod=Mod, data=Data}};
		{stop, Reason} -> {stop, Reason};
		ignore -> ignore;
		Other -> {stop, {invalid_return, Other}}
	end.

%% handle_call/3
handle_call(Request, From, State=#state{queue=Pid, mod=Mod, data=Data}) ->
	Server = self(),
	brick_queue:push(Pid, fun() ->
				try Mod:handle_call(Request, From, Data) of
					{reply, Reply} -> gen_server:reply(From, Reply);
					noreply -> ok;
					{stop, Reason, Reply} ->
						gen_server:reply(From, Reply),
						send_stop(Server, Reason);
					{stop, Reason} -> send_stop(Server, Reason);
					Other -> send_exit(Server, {invalid_return, Other})
				catch _:Reason -> send_exit(Server, Reason)
				end
		end),
	{noreply, State}.

%% handle_cast/2
handle_cast(Msg, State=#state{queue=Pid, mod=Mod, data=Data}) ->
	Server = self(),
	brick_queue:push(Pid, fun() ->
				try Mod:handle_cast(Msg, Data) of
					noreply -> ok;
					{stop, Reason} -> send_stop(Server, Reason);
					Other -> send_exit(Server, {invalid_return, Other})
				catch _:Reason -> send_exit(Server, Reason)
				end
		end),
	{noreply, State}.

%% handle_info/2
handle_info({'EXIT', _FromPid, ?STOP_REASON(Reason)}, State) ->
	{stop, Reason, State};

handle_info({'EXIT', _FromPid, ?EXIT_REASON(Reason)}, _State) ->
	exit(Reason);

handle_info(Info, State=#state{queue=Pid, mod=Mod, data=Data}) ->
	Server = self(),
	brick_queue:push(Pid, fun() ->
				try Mod:handle_info(Info, Data) of
					noreply -> ok;
					{stop, Reason} -> send_stop(Server, Reason);
					Other -> send_exit(Server, {invalid_return, Other})
				catch _:Reason -> send_exit(Server, Reason)
				end
		end),
	{noreply, State}.

%% terminate/2
terminate(Reason, #state{mod=Mod, data=Data}) ->
	Mod:terminate(Reason, Data).

%% code_change/3
code_change(OldVsn, State=#state{mod=Mod, data=Data}, Extra) ->
	case Mod:code_change(OldVsn, Data, Extra) of
		{ok, NewData} -> {ok, State#state{data=NewData}};
		{error, Reason} -> {error, Reason}
	end.

%% ====================================================================
%% Internal functions
%% ====================================================================

send_stop(Server, Reason) ->
	exit(Server, ?STOP_REASON(Reason)).

send_exit(Server, Reason) ->
	exit(Server, ?EXIT_REASON(Reason)).
