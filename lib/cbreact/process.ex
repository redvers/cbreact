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
            |> HashDict.put(:sessionidevents, set2events(sessionid))
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
    newstate = state
    |> extract_modloads(process)
    |> extract_netconns(process)
    |> extract_regmods(process)
    |> extract_filemods(process)
    |> extract_childprocs(process)
    |> extract_crossprocs(process)

    {:noreply, newstate}
  end

  def extract_crossprocs(state, %{"crossproc_count" => crossproc_count, "crossproc_complete" => crossproc_complete}) do
    Enum.map(crossproc_complete, &(process_crossproc_line(&1, state)))
    HashDict.put(state, :crossproc_count_full, crossproc_count)
  end
  def extract_childprocs(state, %{"childproc_count" => childproc_count, "childproc_complete" => childproc_complete}) do
    Enum.map(childproc_complete, &(process_childproc_line(&1, state)))
    HashDict.put(state, :childproc_count_full, childproc_count)
  end
  def extract_filemods(state, %{"filemod_count" => filemod_count, "filemod_complete" => filemod_complete}) do
    Enum.map(filemod_complete, &(process_filemod_line(&1, state)))
    HashDict.put(state, :filemod_count_full, filemod_count)
  end
  def extract_modloads(state, %{"modload_count" => modload_count, "modload_complete" => modload_complete}) do
    Enum.map(modload_complete, &(process_modload_line(&1, state)))
    HashDict.put(state, :modload_count_full, modload_count)
  end
  def extract_netconns(state, %{"netconn_count" => netconn_count, "netconn_complete" => netconn_complete}) do
    Enum.map(netconn_complete, &(process_netconn_line(&1, state)))
    HashDict.put(state, :netconn_count_full, netconn_count)
  end
  def extract_regmods(state, %{"regmod_count" => regmod_count, "regmod_complete" => regmod_complete}) do
    Enum.map(regmod_complete, &(process_regmod_line(&1, state)))
    HashDict.put(state, :regmod_count_full, regmod_count)
  end
  def extract_crossprocs(state, %{"crossproc_count" => crossproc_count}) do
    HashDict.put(state, :crossproc_count_full, crossproc_count)
  end
  def extract_childprocs(state, %{"childproc_count" => childproc_count}) do
    HashDict.put(state, :childproc_count_full, childproc_count)
  end
  def extract_filemods(state, %{"filemod_count" => filemod_count}) do
    HashDict.put(state, :filemod_count_full, filemod_count)
  end
  def extract_regmods(state, %{"regmod_count" => regmod_count}) do
    HashDict.put(state, :regmod_count_full, regmod_count)
  end
  def extract_modloads(state, %{"modload_count" => modload_count}) do
    HashDict.put(state, :modload_count_full, modload_count)
  end
  def extract_netconns(state, %{"netconn_count" => netconn_count}) do
    HashDict.put(state, :netconn_count_full, netconn_count)
  end

  def process_crossproc_line(string, state) do
    [optype, datetime, targetguid, md5, childpath, subtype, privs, tamper] = String.split(string, "|")
    [starttime, endtime] = state[:range]
    eventtime = Timex.Parse.DateTime.Parser.parse(datetime<>"Z", "{ISOz}")
    recordts = Regex.replace(~r/ /, datetime, "T") <> "Z"

    case {(eventtime > starttime), (eventtime < endtime)} do
      {true, true} -> :ets.insert(state[:sessionidevents], {recordts, {:crossproc, {state[:guid], state[:segment_id]}, optype, targetguid, md5, childpath, subtype, privs, tamper}})
      _-> :ok
    end
    state
  end

  def process_childproc_line(string, state) do
    [datetime, childguid, md5, childpath, childpid, startend, tamper] = String.split(string, "|")
    [starttime, endtime] = state[:range]
    eventtime = Timex.Parse.DateTime.Parser.parse(datetime<>"Z", "{ISOz}")
    recordts = Regex.replace(~r/ /, datetime, "T") <> "Z"

    case {(eventtime > starttime), (eventtime < endtime)} do
      {true, true} -> :ets.insert(state[:sessionidevents], {recordts, {:childproc, {state[:guid], state[:segment_id]}, childguid, md5, childpath, childpid, startend, tamper}})
      _-> :ok
    end
    state
  end

  def process_filemod_line(string, state) do
    [operationtype, datetime, filepath, md5, filetype, tamper] = String.split(string, "|")
    [starttime, endtime] = state[:range]
    eventtime = Timex.Parse.DateTime.Parser.parse(datetime<>"Z", "{ISOz}")
    recordts = Regex.replace(~r/ /, datetime, "T") <> "Z"

    case {(eventtime > starttime), (eventtime < endtime)} do
      {true, true} -> :ets.insert(state[:sessionidevents], {recordts, {:filemod, {state[:guid], state[:segment_id]}, operationtype, filepath, md5, filetype, tamper}})
      _-> :ok
    end
    state
  end

  def process_regmod_line(string, state) do
    [operationtype, datetime, regpath, tamper] = String.split(string, "|")
    [starttime, endtime] = state[:range]
    eventtime = Timex.Parse.DateTime.Parser.parse(datetime<>"Z", "{ISOz}")
    recordts = Regex.replace(~r/ /, datetime, "T") <> "Z"

    case {(eventtime > starttime), (eventtime < endtime)} do
      {true, true} -> :ets.insert(state[:sessionidevents], {recordts, {:regmod, {state[:guid], state[:segment_id]}, operationtype, regpath, tamper}})
      _-> :ok
    end
    state
  end

  def process_modload_line(string, state) do
    [datetime, md5, file] = String.split(string, "|")
    [starttime, endtime] = state[:range]
    eventtime = Timex.Parse.DateTime.Parser.parse(datetime<>"Z", "{ISOz}")
    recordts = Regex.replace(~r/ /, datetime, "T") <> "Z"

    case {(eventtime > starttime), (eventtime < endtime)} do
      {true, true} -> :ets.insert(state[:sessionidevents], {recordts, {:modload, {state[:guid], state[:segment_id]},md5, file}})
       _-> :ok
    end
    state
  end

  def process_netconn_line(%{"domain" => domain, "proto" => proto, "local_port" => local_port, "timestamp" => timestamp, "local_ip" => local_ip, "direction" => direction, "remote_port" => remote_port, "remote_ip" => remote_ip}, state) do
    [starttime, endtime] = state[:range]
    eventtime = Timex.Parse.DateTime.Parser.parse(timestamp, "{ISOz}")

    case {(eventtime > starttime), (eventtime < endtime)} do
      {true, true} -> :ets.insert(state[:sessionidevents], {timestamp, {:netconn, {state[:guid], state[:segment_id]}, domain, proto, local_port, local_ip, direction, remote_port, remote_ip}})
      _ -> :ok
    end
  end

  def set2events(sessionid) do
    Atom.to_string(sessionid) <> "events"
    |> String.to_atom
  end


end
