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

-define(BRICK_RPC_FROM(Pid, Ref), {Pid, Ref}).
-define(BRICK_RPC_CALL(From, Msg), {'$call', From, Msg}).
-define(BRICK_RPC_REPLY(Ref, Msg), {'$reply', Ref, Msg}).
-define(BRICK_RPC_CAST(Msg), {'$cast', Msg}).

-define(BRICK_RPC_NONAME, '$brick_rpc_noname').