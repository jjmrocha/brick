%%
%% Copyright 2017 Joaquim Rocha <jrocha@gmailbox.org>
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

-define(CLUSTER_NAME(Cluster, Id), {'$brick', Cluster, Id}).

-define(RESOLVE_REQUEST(From, Ref), {'$brick_resolve_request', From, Ref}).
-define(RESOLVE_RESPONSE(Ref, Argument), {'$brick_resolve_response', Ref, Argument}).
