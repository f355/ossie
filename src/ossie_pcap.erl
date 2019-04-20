%% MGW Nat testing code

%% (C) 2011 by Harald Welte <laforge@gnumonks.org>
%% (C) 2011 OnWaves
%%
%% All Rights Reserved
%%
%% This program is free software; you can redistribute it and/or modify
%% it under the terms of the GNU Affero General Public License as
%% published by the Free Software Foundation; either version 3 of the
%% License, or (at your option) any later version.
%%
%% This program is distributed in the hope that it will be useful,
%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%% GNU General Public License for more details.
%%
%% You should have received a copy of the GNU Affero General Public License
%% along with this program.  If not, see <http://www.gnu.org/licenses/>.
%%
%% Additional Permission under GNU AGPL version 3 section 7:
%%
%% If you modify this Program, or any covered work, by linking or
%% combining it with runtime libraries of Erlang/OTP as released by
%% Ericsson on http://www.erlang.org (or a modified version of these
%% libraries), containing parts covered by the terms of the Erlang Public
%% License (http://www.erlang.org/EPLICENSE), the licensors of this
%% Program grant you additional permission to convey the resulting work
%% without the need to license the runtime libraries of Erlang/OTP under
%% the GNU Affero General Public License. Corresponding Source for a
%% non-source form of such a combination shall include the source code
%% for the parts of the runtime libraries of Erlang/OTP used as well as
%% that of the covered work.

-module(ossie_pcap).
-author("Harald Welte <laforge@gnumonks.org>").
-export([pcap_apply/3]).

-define(NODEBUG, 1).

-include_lib("eunit/include/eunit.hrl").
-include_lib("pkt/include/pkt_sctp.hrl").

-record(loop_data, {
                    epcap_pid,
                    args,
                    pkt_nr
                   }).

pcap_apply(File, Filter, Args) ->
    {ok, Pid} = epcap:start_link([{file, File}, {filter, Filter}]),
    loop(#loop_data{args = Args, pkt_nr = 1, epcap_pid = Pid}).

-record(packet, {data_link_type, time_stamp, packet_length, packet}).

loop(L = #loop_data{args=Args, pkt_nr = PktNr, epcap_pid = Pid}) ->
    receive
        #packet{data_link_type=Datalink, packet=Packet} ->
            Decaps = pkt:decapsulate({pkt:dlt(Datalink), Packet}),
            handle_pkt_cb(PktNr, Decaps, Args),
            loop(L#loop_data{pkt_nr = PktNr+1});
        {epcap, eof} ->
            ?debugFmt("EOF from PCAP~n", []),
            epcap:stop(Pid),
            {ok, PktNr-1};
        Err ->
            erlang:exit({?MODULE, ?LINE, Err})
    end.


handle_pkt_cb(PktNr, [Ether, IP, Hdr, _Payload], Args) ->
    ?debugFmt("~p:~n  ~p/~p~n", [IP, Hdr, Payload]),
    case Hdr of
        #sctp{chunks = Chunks} ->
            Path = [{epcap_pkt_nr, PktNr}, Ether, IP, Hdr],
            handle_sctp_chunks(Chunks, Path, Args);
        _ ->
            ok
    end.

handle_sctp_chunks([], _Path, _Args) ->
    ok;
handle_sctp_chunks([Head|Tail], Path, Args) ->
    RewriteFn = proplists:get_value(rewrite_fn, Args),
    case Head of
        #sctp_chunk{type = 0,
                    payload=#sctp_chunk_data{ppi=Ppi,
                                             data=Data}} ->
            RewriteFn(sctp, from_msc, Path, Ppi, Data);
        _ ->
            ok
    end,
    handle_sctp_chunks(Tail, Path, Args).
