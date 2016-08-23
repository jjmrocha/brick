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

-module(brick_basic).

-include("brick_rpc.hrl").
-define(BRICK_BASIC_NONAME, '$brick_basic_noname').

%% ====================================================================
%% Callback functions
%% ====================================================================

-callback init(Args :: term()) ->
	{ok, State :: term()} |
	{ok, State :: term(), timeout() | hibernate} |
	{stop, Reason :: term()}.

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
	
-optional_callbacks([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start/2, start/3]).
-export([start_link/2, start_link/3]).
-export([stop/1, stop/3]).

-export([cast/2]).
-export([call/2, call/3]).
-export([reply/2]).

%% ====================================================================
%% System exports
%% ====================================================================
-export([system_continue/3, system_terminate/4, system_code_change/4]).

%% ====================================================================
%% Internal exports
%% ====================================================================
-export([do_init/4, wakeup/5]).

%% ====================================================================
%% API Implementation
%% ====================================================================

start(Mod, Args) -> start(?BRICK_BASIC_NONAME, Mod, Args).

start(Name, Mod, Args) ->
	Meta = meta(Mod),
	proc_lib:start(?MODULE, do_init, [self(), Name, Meta, Args]).
	
start_link(Mod, Args) -> start_link(?BRICK_BASIC_NONAME, Mod, Args).

start_link(Name, Mod, Args) ->
	Meta = meta(Mod),
	proc_lib:start_link(?MODULE, do_init, [self(), Name, Meta, Args]).
	
stop(Process) -> stop(Process, normal, infinity).

stop(Process, Reason, Timeout) -> proc_lib:stop(Process, Reason, Timeout).

cast(Process, Msg) -> brick_rpc:cast(Process, Msg).

call(Process, Msg) -> brick_rpc:call(Process, Msg).

call(Process, Msg, Timeout) -> brick_rpc:call(Process, Msg, Timeout).

reply(From, Msg) -> brick_rpc:reply(From, Msg).

%% ====================================================================
%% Internal functions
%% ====================================================================

-record(module_meta_record, {mod, init, handle_call, handle_cast, handle_info, terminate, code_change}).

meta(Module) ->
	Meta = #module_meta_record{
		mod=Module,
		init=erlang:function_exported(Module, init, 1), 
		handle_call=erlang:function_exported(Module, handle_call, 4), 
		handle_cast=erlang:function_exported(Module, handle_cast, 2), 
		handle_info=erlang:function_exported(Module, handle_info, 2), 
		terminate=erlang:function_exported(Module, terminate, 2), 
		code_change=erlang:function_exported(Module, code_change, 3)
	},
	if 
		Meta#module_meta_record.handle_call,
		Meta#module_meta_record.handle_cast,
		Meta#module_meta_record.handle_info -> Meta;
		true -> exit(invalid_module)
	end.

%% ====================================================================
%% Server functions
%% ====================================================================
do_init(Parent, Name, Meta=#module_meta_record{init=DoInit, mod=Mod}, Args) ->
	register_name(Name),
	Debug = sys:debug_options([]),
	case invoke(DoInit, Mod, init, Args, {ok, []}) of
		{ok, State} ->
			proc_lib:init_ack(Parent, {ok, self()}), 	
			loop(Parent, Debug, Name, Meta, State, infinity);
		{ok, State, TimeOrHib} ->
			proc_lib:init_ack(Parent, {ok, self()}), 	
			loop(Parent, Debug, Name, Meta, State, TimeOrHib);
		{stop, Reason} -> stop_init(Parent, Name, Reason);
		{'EXIT', Reason} -> stop_init(Parent, Name, Reason);
		Other -> stop_init(Parent, Name, {bad_return_value, Other})
	end.
	
stop_init(Parent, Name, Error) ->
	unregister_name(Name),
	proc_lib:init_ack(Parent, {error, Error}),
	exit(Error).
	
register_name(?BRICK_BASIC_NONAME) -> ok;
register_name(Name) -> register(Name, self()).

unregister_name(?BRICK_BASIC_NONAME) -> ok;
unregister_name(Name) -> unregister(Name).

invoke(true, Mod, Fun, Args, _) -> catch apply(Mod, Fun, Args);
invoke(false, _, _, _, Return) -> Return.

loop(Parent, Debug, Name, Meta, State, hibernate) -> 
	proc_lib:hibernate(?MODULE, wakeup, [Parent, Debug, Name, Meta, State]);
loop(Parent, Debug, Name, Meta, State, Timeout) -> 
	Request = receive
		Input -> Input
	after Timeout -> timeout
	end,
	handle_request(Request, Parent, Debug, Name, Meta, State, Timeout).
	
handle_request(?BRICK_RPC_CALL(From, Msg), Parent, Debug, Name, Meta, State, _) ->
	do_call(From, Msg, Parent, Debug, Name, Meta, State);
handle_request(?BRICK_RPC_CAST(Msg), Parent, Debug, Name, Meta, State, _) ->
	do_cast(Msg, Parent, Debug, Name, Meta, State);	
handle_request({system, From, Request}, Parent, Debug, Name, Meta, State, TimeOrHib) ->
	sys:handle_system_msg(Request, From, Parent, ?MODULE, Debug, [Name, Meta, State, TimeOrHib]);
handle_request({'EXIT', Parent, Reason}, Parent, _Debug, Name, Meta, State, _) ->
	terminate(Reason, Name, Meta, State);	
handle_request(Info, Parent, Debug, Name, Meta, State, _) -> 
	do_info(Info, Parent, Debug, Name, Meta, State).
	
do_call(From, Msg, Parent, Debug, Name, Meta=#module_meta_record{handle_call=DoCall, mod=Mod}, State) -> 
	Return = invoke(DoCall, Mod, handle_call, [Msg, From, State], {noreply, State}),
	handle_return(Return, From, Parent, Debug, Name, Meta).

do_cast(Msg, Parent, Debug, Name, Meta=#module_meta_record{handle_cast=DoCast, mod=Mod}, State) -> 
	Return = invoke(DoCast, Mod, handle_cast, [Msg, State], {noreply, State}),
	handle_return(Return, none, Parent, Debug, Name, Meta).
	
do_info(Info, Parent, Debug, Name, Meta=#module_meta_record{handle_info=DoInfo, mod=Mod}, State) -> 
	Return = invoke(DoInfo, Mod, handle_info, [Info, State], {noreply, State}),
	handle_return(Return, none, Parent, Debug, Name, Meta).
	
handle_return({reply, Reply, NewState}, From, Parent, Debug, Name, Meta) -> 
	reply(From, Reply),
	loop(Parent, Debug, Name, Meta, NewState, infinity);
handle_return({reply, Reply, NewState, TimeOrHib}, From, Parent, Debug, Name, Meta) ->
	reply(From, Reply),
	loop(Parent, Debug, Name, Meta, NewState, TimeOrHib);			
handle_return({noreply, NewState}, _, Parent, Debug, Name, Meta) -> 
	loop(Parent, Debug, Name, Meta, NewState, infinity);
handle_return({noreply, NewState, TimeOrHib}, _, Parent, Debug, Name, Meta) -> 
	loop(Parent, Debug, Name, Meta, NewState, TimeOrHib);		
handle_return({stop, Reason, Reply, NewState}, From, _, _, Name, Meta) ->
	reply(From, Reply),
	terminate(Reason, Name, Meta, NewState);
handle_return({stop, Reason, NewState}, _, _, _, Name, Meta) -> 
	terminate(Reason, Name, Meta, NewState).

terminate(Reason, Name, #module_meta_record{terminate=DoTerminate, mod=Mod}, State) ->
	invoke(DoTerminate, Mod, terminate, [Reason, State], ok),
	unregister_name(Name),
	exit(Reason).

system_continue(Parent, Debug, [Name, Meta, State, TimeOrHib]) -> loop(Parent, Debug, Name, Meta, State, TimeOrHib).

system_terminate(Reason, _Parent, _Debug, [Name, Meta, State, _]) -> terminate(Reason, Name, Meta, State).

system_code_change([Name, Meta=#module_meta_record{code_change=DoCodeChange, mod=Mod}, State, TimeOrHib], _Module, OldVsn, Extra) -> 
	case invoke(DoCodeChange, Mod, code_change, [OldVsn, State, Extra], {ok, State}) of
		{ok, NewState} -> {ok, [Name, Meta, NewState, TimeOrHib]};
		{'EXIT', Reason} -> {error, Reason};
		Other -> Other
	end.
	
wakeup(Parent, Debug, Name, Meta, State) -> 
	receive
		Request -> handle_request(Request, Parent, Debug, Name, Meta, State, hibernate)
	end.