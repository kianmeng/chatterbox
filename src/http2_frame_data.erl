-module(http2_frame_data).

-include("http2.hrl").

-export([
         format/1,
         read_binary/2,
         to_frames/3,
         to_binary/1,
         data/1,
         new/1
        ]).

-behaviour(http2_frame).

-record(data, {
    data :: iodata()
  }).
-type payload() :: #data{}.
-export_type([payload/0]).

-spec data(payload()) -> iodata().
data(#data{data=D}) ->
    D.

-spec format(payload()) -> iodata().
format(Payload) ->
    BinToShow = case size(Payload) > 7 of
        false ->
            Payload#data.data;
        true ->
            <<Start:8/binary,_/binary>> = Payload#data.data,
            Start
    end,
    io_lib:format("[Data: {data: ~p ...}]", [BinToShow]).

-spec new(binary()) -> payload().
new(Data) ->
    #data{data=Data}.

-spec read_binary(binary(), frame_header()) ->
    {ok, payload(), binary()}.
read_binary(Bin, _H=#frame_header{length=0}) ->
    {ok, #data{data= <<>>}, Bin};
read_binary(Bin, H=#frame_header{length=L}) ->
    lager:debug("read_binary L: ~p, actually: ~p", [L, byte_size(Bin)]),
    <<PayloadBin:L/binary,Rem/bits>> = Bin,
    case http2_padding:read_possibly_padded_payload(PayloadBin, H) of
        {error, Code} ->
            {error, Code};
        Data ->
            {ok, #data{data=Data}, Rem}
    end.

-spec to_frames(stream_id(), iodata(), settings()) -> [http2_frame:frame()].
to_frames(StreamId, IOList, Settings)
  when is_list(IOList) ->
    to_frames(StreamId, iolist_to_binary(IOList), Settings);
to_frames(StreamId, Data, S=#settings{max_frame_size=MFS}) ->
    L = byte_size(Data),
    case L >= MFS of
        false ->
            [{#frame_header{
                 length=L,
                 type=?DATA,
                 flags=?FLAG_END_STREAM,
                 stream_id=StreamId
                }, #data{data=Data}}];
        true ->
            <<ToSend:MFS/binary,Rest/binary>> = Data,
            [{#frame_header{
                 length=MFS,
                 type=?DATA,
                 stream_id=StreamId
                },
              #data{data=ToSend}} | to_frames(StreamId, Rest, S)]
    end.


-spec to_binary(payload()) -> iodata().
to_binary(#data{data=D}) ->
    D.
