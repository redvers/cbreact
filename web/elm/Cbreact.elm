module Cbreact where

import Html exposing (..)
import Html.Attributes exposing (..)
import Debug

-- MODEL
type alias CbSensor =
  {
    id : Int,
    computer_name : String,
    os_environment_display_string : String,
    clock_delta : Int,
    uptime : Int,
    sensor_uptime : Int,
    last_update : String,
    status : String,
    num_eventlog_bytes : Int,
    build_version_string : String,
    registration_time : String,
    last_checkin_time : String,
    next_checkin_time : String,
    group_id : Int,
    num_storefiles_bytes : Int
  }

type alias CbProc =
  {
    guid : String,
    cmdline : String,
    sensor_id : Int,
    username : String
  }
    
type alias ScrollData = String
type alias CbEventNetconn =
  { evId : Int,
    procguid : String,
    timestamp : String,
    domain : String,
    proto : Int,
    local_ip : Int,
    local_port : Int,
    direction : Bool,
    remote_ip : Int,
    remote_port : Int }

type alias Model =
  {
    sensorList : List CbSensor,
    procList : List CbProc,
    statusScroll : List ScrollData,
    eventList : List CbEventNetconn,
    sessionRange : List String
  }

initialModel : Model
initialModel =
    {
      sensorList = [],
      procList = [],
      statusScroll = ["Hello World"], 
      eventList = [],
      sessionRange = []
    }

-- UPDATE
type Action = NoOp | EvUpdate Model | AddSensor CbSensor | DebugLogs ScrollData

update : Action -> Model -> Model
update action model =
  case action of
    NoOp ->
      model
    EvUpdate cbev ->
      cbev
    DebugLogs cbdebug ->
      { model |
        statusScroll <- model.statusScroll ++ [ cbdebug ]
      }
    AddSensor cbsensor ->
      { model |
        sensorList <- model.sensorList ++ [ cbsensor ] 
      }


-- VIEW
view : Model -> Html
view model =
  div [] [
    ul [] ( List.map cbsensorfn model.sensorList ),
    ul [] ( List.map cbprocfn model.procList ),
    ul [] ( List.map cbeventfn model.eventList ),
    ul [] ( List.map cbdebfn model.statusScroll )
  ]

cbdebfn : ScrollData -> Html
cbdebfn scrollData =
   li [] [ text (toString scrollData) ]

cbeventfn : CbEventNetconn -> Html
cbeventfn cbevent =
   li [] [ text (toString cbevent) ]

cbsensorfn : CbSensor -> Html
cbsensorfn cbsensor =
   li [] [ text (toString cbsensor) ]

cbprocfn : CbProc -> Html
cbprocfn cbproc =
   li [] [ text (toString cbproc) ]

-- PORTS
port cbev : Signal Model
port cbsensor : Signal CbSensor
port cbdebug : Signal ScrollData


-- SIGNALS
--type Action = NoOp | EvUpdate Model | AddSensor CbSensor | DebugLogs ScrollData
inbox : Signal.Mailbox Action
inbox =
  Signal.mailbox NoOp

cbdebugfn : Signal Action
cbdebugfn =
  Signal.map DebugLogs cbdebug

cbportfn : Signal Action
cbportfn =
  Signal.map AddSensor cbsensor

cbevfn : Signal Action
cbevfn =
  Signal.map EvUpdate cbev

actions : Signal Action
actions =
  Signal.mergeMany [ cbportfn, cbevfn, cbdebugfn ]

model : Signal Model
model =
  Signal.foldp update initialModel actions

main : Signal Html
main =
  Signal.map view model

