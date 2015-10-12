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
    eventList : List CbEventNetconn,
    sessionRange : List String
  }

initialModel : Model
initialModel =
    {
      sensorList = [],
      procList = [],
      eventList = [],
      sessionRange = []
    }

-- UPDATE
type Action = NoOp | EvUpdate Model | AddSensor CbSensor

update : Action -> Model -> Model
update action model =
  case action of
    NoOp ->
      model
    EvUpdate cbev ->
      cbev
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
    ul [] ( List.map cbeventfn model.eventList )
  ]

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


-- SIGNALS
-- type Action = NoOp | EvUpdate Model | AddSensor CbSensor
inbox : Signal.Mailbox Action
inbox =
  Signal.mailbox NoOp

cbportfn : Signal Action
cbportfn =
  Signal.map AddSensor cbsensor

cbevfn : Signal Action
cbevfn =
  Signal.map EvUpdate cbev

actions : Signal Action
actions =
  Signal.merge cbportfn cbevfn

model : Signal Model
model =
  Signal.foldp update initialModel actions

main : Signal Html
main =
  Signal.map view model

