import "deps/phoenix_html/web/static/js/phoenix_html"
import socket from "./socket"

var elmDiv = document.getElementById("elm-main"),
  elmApp = Elm.embed(Elm.Cbreact, elmDiv, {
    cbev: {
      sensorList: [],
      procList: [],
      statusScroll: ["initian cbev"],
      eventList: [],
      sessionRange: []
    },
    cbsensor: {
      id: 0,
      computer_name: "none",
      os_environment_display_string: "none",
      clock_delta: 0,
      uptime: 0,
      sensor_uptime: 0,
      last_update: "none",
      status: "none",
      num_eventlog_bytes: 0,
      build_version_string: "none",
      registration_time: "none",
      last_checkin_time: "none",
      next_checkin_time: "none",
      group_id: 0,
      num_storefiles_bytes: 0
    },
	cbdebug: "initial cbdebug"
  }
);

let channel = socket.channel("cbreact:lobby", {})
channel.join()
  .receive("ok", resp => { console.log("joined", resp);
          elmApp.ports.cbev.send({
              sensorList: [],
              procList: [],
              statusScroll: ["onjoin channel"],
              eventList: [],
              sessionRange: []
          });
          channel.push("initialSensor", { sensorid: 1 })
            .receive("ok", payload => {
            	console.log("Been asked to join cbreact:", payload.sessionid);
				let newchannel = socket.channel("cbreact:" + payload.sessionid, {})
				newchannel.join()
				  .receive("ok", resp => { console.log("Joined!", resp) })
				  .receive("error", resp => { console.log("Failed to join!", resp) })

				newchannel.on("sensorUpdate", payload => {
					console.log("Got sensor notification", payload);
					elmApp.ports.cbsensor.send(payload);
				});
				newchannel.on("debuglogs", payload => {
					console.log("Got debug notification", payload);
					elmApp.ports.cbdebug.send(payload.message);
				});






         	})
				
            .receive("error", payload => {
            	console.log(payload.message);
         	})
          })
  .receive("error", resp => { console.log("No Join", resp) })



