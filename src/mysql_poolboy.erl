%% MySQL/OTP + Poolboy
%% Copyright (C) 2014 Raoul Hess
%%
%% This file is part of MySQL/OTP + Poolboy.
%%
%% MySQL/OTP + Poolboy is free software: you can redistribute it and/or modify it under
%% the terms of the GNU Lesser General Public License as published by the Free
%% Software Foundation, either version 3 of the License, or (at your option)
%% any later version.
%%
%% This program is distributed in the hope that it will be useful, but WITHOUT
%% ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
%% FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for
%% more details.
%%
%% You should have received a copy of the GNU Lesser General Public License
%% along with this program. If not, see <https://www.gnu.org/licenses/>.

%% @doc Only add_pool/3 needs mysql_poolboy_app started to be able to add
%% pools to the supvervisor.
-module(mysql_poolboy).

-export([add_pool/3,
         checkin/2, checkout/1,
         child_spec/3,
         execute/3, execute/4,
         query/2, query/3, query/4,
         transaction/2, transaction/3, transaction/4,
         with/2]).

%% @doc Adds a pool to the started mysql_poolboy application.
add_pool({GlobalOrLocal, PoolName}, PoolArgs, MysqlArgs) ->
    %% We want strategy fifo as default instead of lifo.
    PoolSpec = child_spec({GlobalOrLocal, PoolName}, PoolArgs, MysqlArgs),
    supervisor:start_child(mysql_poolboy_sup, PoolSpec).

%% @doc Returns a mysql connection to the given pool.
checkin({GlobalOrLocal, PoolName}, Connection) ->
    poolboy:checkin({GlobalOrLocal, PoolName}, Connection).

%% @doc Checks out a mysql connection from a given pool.
checkout({GlobalOrLocal, PoolName}) ->
    poolboy:checkout({GlobalOrLocal, PoolName}).

%% @doc Creates a supvervisor:child_spec. When the need to
%% supervise the pools in another way.
child_spec({GlobalOrLocal, PoolName}, PoolArgs, MysqlArgs) ->
    PoolArgs1 = case proplists:is_defined(strategy, PoolArgs) of
        true  ->
            [{name, {GlobalOrLocal, PoolName}}, {worker_module, mysql} | PoolArgs];
        false ->
            %% Use fifo by default. MySQL closes unused connections after a certain time.
            %% Fifo causes all connections to be regularily used which prevents them from
            %% being closed.,
            [{strategy, fifo}, {name, {GlobalOrLocal, PoolName}}, {worker_module, mysql} | PoolArgs]
    end,
    poolboy:child_spec(PoolName, PoolArgs1, MysqlArgs).

%% @doc Execute a mysql prepared statement with given params.
execute({GlobalOrLocal, PoolName}, StatementRef, Params) ->
    poolboy:transaction({GlobalOrLocal, PoolName}, fun(MysqlConn) ->
        mysql:execute(MysqlConn, StatementRef, Params)
    end).

%% @doc Execute a mysql prepared statement with given params and timeout
execute({GlobalOrLocal, PoolName}, StatementRef, Params, Timeout) ->
    poolboy:transaction({GlobalOrLocal, PoolName}, fun(MysqlConn) ->
        mysql:execute(MysqlConn, StatementRef, Params, Timeout)
    end).

%% @doc Executes a query to a mysql connection in a given pool.
query({GlobalOrLocal, PoolName}, Query) ->
    poolboy:transaction({GlobalOrLocal, PoolName}, fun(MysqlConn) ->
        mysql:query(MysqlConn, Query)
    end).

%% @doc Executes a query to a mysql connection in a given pool with either
%% list of query parameters or a timeout value.
query({GlobalOrLocal, PoolName}, Query, ParamsOrTimeout) ->
    poolboy:transaction({GlobalOrLocal, PoolName}, fun(MysqlConn) ->
        mysql:query(MysqlConn, Query, ParamsOrTimeout)
    end).

%% @doc Executes a query to a mysql connection in a given pool with both
%% a list of query parameters and a timeout value.
query({GlobalOrLocal, PoolName}, Query, Params, Timeout) ->
    poolboy:transaction({GlobalOrLocal, PoolName}, fun(MysqlConn) ->
        mysql:query(MysqlConn, Query, Params, Timeout)
    end).

%% @doc Wrapper to poolboy:transaction/2. Since it is not a mysql transaction.
%% Example instead of:
%% Conn = mysql_poolboy:checkout(mypool),
%% try
%%     mysql:query(Conn, "SELECT...")
%%  after
%%     mysql_poolboy:checkin(mypool, Conn)
%%  end.
%%
%% mysql_poolboy:with(mypool, fun (Conn) -> mysql:query(Conn, "SELECT...") end).
with({GlobalOrLocal, PoolName}, Fun) when is_function(Fun, 1) ->
    poolboy:transaction({GlobalOrLocal, PoolName}, Fun).

%% @doc Executes a mysql transaction fun. The fun needs to take one argument
%% which is the mysql connection.
transaction({GlobalOrLocal, PoolName}, TransactionFun) when is_function(TransactionFun, 1) ->
    poolboy:transaction({GlobalOrLocal, PoolName}, fun(MysqlConn) ->
        mysql:transaction(MysqlConn, TransactionFun, [MysqlConn], infinity)
    end).

%% @doc Executes a transaction fun. Args list needs be the same length as
%% TransactionFun arity - 1.
transaction({GlobalOrLocal, PoolName}, TransactionFun, Args)
    when is_function(TransactionFun, length(Args) + 1) ->
    poolboy:transaction({GlobalOrLocal, PoolName}, fun(MysqlConn) ->
        mysql:transaction(MysqlConn, TransactionFun, [MysqlConn | Args],
                          infinity)
    end).

%% @doc Same as transaction/3 but with the number of retries the mysql
%% transaction should try to execute.
transaction({GlobalOrLocal, PoolName}, TransactionFun, Args, Retries)
    when is_function(TransactionFun, length(Args) + 1) ->
    poolboy:transaction({GlobalOrLocal, PoolName}, fun(MysqlConn) ->
        mysql:transaction(MysqlConn, TransactionFun, [MysqlConn | Args],
                          Retries)
    end).
