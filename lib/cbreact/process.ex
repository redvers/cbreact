require Logger
defmodule Cbreact.Process do
  use GenServer

  def start_link({guid, segment_id, range, sessionid}) do
    GenServer.start_link(__MODULE__, {guid, segment_id, range, sessionid})
  end

  def init({guid, segment_id, [startdate, enddate], sessionid}) do
    starttime = Timex.Parse.DateTime.Parser.parse(startdate<>"Z", "{ISOz}")
    endtime = Timex.Parse.DateTime.Parser.parse(enddate<>"Z", "{ISOz}")
    
    state = HashDict.new
            |> HashDict.put(:cbclientapi, struct(Cbclientapi, Application.get_env(:cbclientapi, Cbclientapi))) 
            |> HashDict.put(:guid, guid)
            |> HashDict.put(:segment_id, segment_id)
            |> HashDict.put(:range, [starttime, endtime])
            |> HashDict.put(:status, :pending)
            |> HashDict.put(:sessionid, sessionid)
    {:ok, state}
  end

  def handle_cast(:pull, state) do
    Logger.debug("Receieved pull request for #{state[:guid]}")
    url = "https://#{state[:cbclientapi].hostname}:#{state[:cbclientapi].port}/api/v2/process/#{state[:guid]}/#{state[:segment_id]}/event"
    case :hackney.get(url, [{"X-Auth-Token", state[:cbclientapi].api}], '', [ssl_options: [insecure: true], async: true, pool: :cbpool]) do
      {:ok, ref} -> newstate = HashDict.put(state, :status, {:requested, ref})
                               |> HashDict.put(:json, "")
                    {:noreply, newstate}
      {:error, error} -> Logger.debug("Unable to request hackney from pool #{inspect(error)}, re-requesting")
                                    GenServer.cast(self, :pull)
                                    {:noreply, state}
    end
  end

  def handle_info({:hackney_response, ref, string}, state) when is_binary(string) do
    newstate = HashDict.put(state, :json, state[:json] <> string)
    {:noreply, newstate}
  end
  def handle_info({:hackney_response, _ref, error = {:error, _}}, state) do
    Logger.debug("I failed my network connection with #{inspect(error)}")
    GenServer.cast(self, :pull)
    {:noreply, state}
  end
  def handle_info({:hackney_response, _, {:headers, _}}, state) do
    {:noreply, state}
  end
  def handle_info({:hackney_response, _, {:status, 200, "OK"}}, state) do
    {:noreply, state}
  end
  def handle_info({:hackney_response, ref, :done}, state) do
    %{"process" => process} = JSX.decode!(state[:json])
    newstate = process
    |> extract_modloads(state)
    :gproc.reg({:p, :l, state[:sessionid]}, {state[:guid], state[:segment_id]})

    {:noreply, newstate}
  end

  def extract_modloads(%{"modload_count" => modload_count, "modload_complete" => modload_complete}, state) do
#    Logger.debug(modload_count)
    Enum.reduce(modload_complete, state, fn(x, acc) -> process_modload_line(x, acc) end)
    |> HashDict.put(:modload_count_full, modload_count)
  end
  def extract_modloads(%{"modload_count" => modload_count}, state) do
    Logger.debug(modload_count)
  end

  def process_modload_line(string, state) do
    [datetime, md5, file] = String.split(string, "|")
    [starttime, endtime] = state[:range]
    eventtime = Timex.Parse.DateTime.Parser.parse(datetime<>"Z", "{ISOz}")

    ds = HashDict.get(state, :eventlist, HashDict.new)
    newds =
    case {(eventtime > starttime), (eventtime < endtime), HashDict.get(ds, datetime, [])} do
      {true, true, []} -> [ {:modload, md5, file} ]
      {true, true, pds} -> [ {:modload, md5, file} | pds ]
      {_   , _   , pds} -> pds
    end

    newdsx = HashDict.put(ds, datetime, newds)
    Logger.debug(inspect(newdsx))
    newstate = HashDict.put(state, :eventlist, newdsx)
  end








end
