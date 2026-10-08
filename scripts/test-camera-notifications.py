import datetime
import json
import sys
import unittest

from jinja2 import StrictUndefined
from jinja2.nativetypes import NativeEnvironment


config = json.load(sys.stdin)
automations = {item["id"]: item for item in config["automation"]}
env = NativeEnvironment(undefined=StrictUndefined)
now = datetime.datetime.now(datetime.timezone.utc)


def render(value, context):
    if isinstance(value, dict):
        return {key: render(item, context) for key, item in value.items()}
    if isinstance(value, list):
        return [render(item, context) for item in value]
    if isinstance(value, str) and "{{" in value:
        return env.from_string(value).render(context)
    return value


def evaluate(automation_id, trigger, states=None):
    states = states or {}
    context = {
        "trigger": trigger,
        "is_state": lambda entity, state: states.get(entity, "idle" if entity.startswith("timer.") else "off") == state,
        "now": lambda: now,
        "as_timestamp": lambda value: value.timestamp(),
    }
    automation = automations[automation_id]
    for key, value in automation.get("variables", {}).items():
        context[key] = render(value, context)
    for condition in automation.get("conditions", []):
        if condition["condition"] == "template":
            accepted = render(condition["value_template"], context)
        else:
            accepted = context["is_state"](condition["entity_id"], condition["state"])
        if not accepted:
            return None
    return render(automation["actions"], context)


def review(severity="alert", objects=None, kind="new"):
    return {"payload_json": {
        "type": kind,
        "after": {
            "id": "100-review", "camera": "front_right", "severity": severity,
            "start_time": 100,
            "data": {"detections": ["99-event"], "objects": objects or ["person"], "thumb_time": 101},
        },
    }}


def car(before=False, after=True, kind="update", event_id="99-car", camera="front_right", false_positive=False):
    return {"payload_json": {
        "type": kind,
        "before": {"current_zones": ["podjazd_prawy"] if before else []},
        "after": {
            "id": event_id, "camera": camera, "label": "car", "false_positive": false_positive,
            "current_zones": ["podjazd_prawy"] if after else [],
            "snapshot": {"frame_time": 101}, "frame_time": 102,
        },
    }}


class NotificationTests(unittest.TestCase):
    def test_confirmed_reviews_and_incident_media(self):
        self.assertIsNone(evaluate("frigate_person_alert", review("detection")))
        self.assertIsNone(evaluate("frigate_person_alert", review(objects=["car"])))
        result = evaluate("frigate_person_alert", review())
        notification = result[0]["data"]
        self.assertEqual(notification["data"]["tag"], "frigate-review-100-review")
        self.assertIn("100-review/front_right/review_thumbnail.webp", notification["data"]["image"])
        self.assertIn("99-event/clip.mp4", notification["data"]["actions"][0]["uri"])
        self.assertIn("camera-front_right", notification["data"]["actions"][1]["uri"])
        self.assertEqual(notification["data"]["actions"][2]["action"], "SNOOZE_CAMERA_front_right_30M")
        final = evaluate("frigate_person_alert", review(kind="end"))[0]["data"]
        self.assertEqual(final["data"]["tag"], notification["data"]["tag"])
        self.assertNotEqual(final["data"]["image"], notification["data"]["image"])
        self.assertTrue(final["data"]["alert_once"])

    def test_individual_car_arrivals_departures_and_updates(self):
        entered = evaluate("frigate_driveway_car_transitions", car())[0]["data"]
        self.assertEqual(entered["title"], "Car arrived")
        self.assertEqual(entered["data"]["channel"], "Cars")
        self.assertIn("99-car/snapshot.jpg", entered["data"]["image"])
        self.assertIsNone(evaluate("frigate_driveway_car_transitions", car(True, True)))
        self.assertEqual(evaluate("frigate_driveway_car_transitions", car(True, False))[0]["data"]["title"], "Car left")
        self.assertIsNone(evaluate("frigate_driveway_car_transitions", car(camera="front_left")))
        self.assertIsNone(evaluate("frigate_driveway_car_transitions", car(false_positive=True)))
        self.assertIsNone(evaluate("frigate_driveway_car_transitions", car(True, False, "end")))
        present = evaluate("frigate_driveway_car_transitions", car(kind="new"))[0]["data"]
        self.assertEqual(present["title"], "Car detected")
        second = evaluate("frigate_driveway_car_transitions", car(event_id="100-car"))[0]["data"]
        self.assertNotEqual(second["data"]["tag"], entered["data"]["tag"])
        final = evaluate("frigate_driveway_car_transitions", car(True, True, "end"))[0]["data"]
        self.assertTrue(final["data"]["alert_once"])

    def test_selective_and_global_snoozing(self):
        resumed = config["script"]["camera_alerts_resume"]["sequence"][0]["target"]["entity_id"]
        self.assertEqual(set(resumed), {"timer." + name for name in config["timer"]})
        states = {"timer.camera_alerts_snooze_cars": "active"}
        self.assertIsNone(evaluate("frigate_driveway_car_transitions", car(), states))
        self.assertIsNotNone(evaluate("frigate_person_alert", review(), states))
        states = {"timer.camera_alerts_snooze_front_left": "active"}
        self.assertIsNotNone(evaluate("frigate_driveway_car_transitions", car(), states))
        states = {"timer.camera_alerts_snooze_front_right": "active"}
        self.assertIsNone(evaluate("frigate_person_alert", review(), states))
        states = {"timer.camera_alerts_snooze": "active"}
        self.assertIsNone(evaluate("frigate_driveway_car_transitions", car(), states))
        action = {"event": {"data": {"action": "SNOOZE_CAMERA_front_right_30M"}}}
        rendered = evaluate("camera_alert_selective_snooze", action)
        self.assertEqual(rendered[0]["default"][0]["data"]["camera_id"], "front_right")
        self.assertIsNone(evaluate("camera_alert_selective_snooze", {"event": {"data": {"action": "unrelated"}}}))

    def test_health_templates_and_recovery_deduplication(self):
        sensor = config["mqtt"]["sensor"][0]
        stats = {"service": {"storage": {"/var/lib/frigate/recordings": {"free": 102400}}}}
        self.assertEqual(render(sensor["value_template"], {"value_json": stats}), 100)
        for sensor in config["mqtt"]["binary_sensor"]:
            if sensor["unique_id"].endswith("stream_healthy"):
                camera = sensor["unique_id"].removeprefix("frigate_").removesuffix("_stream_healthy")
                for fps, expected in [(2, "ON"), (0, "OFF")]:
                    self.assertEqual(render(sensor["value_template"], {"value_json": {"cameras": {camera: {"camera_fps": fps}}}}), expected)
        trigger = {"id": "recovery", "entity_id": "binary_sensor.frigate_front_right_stream_healthy", "to_state": {"name": "Right camera", "state": "on"}}
        self.assertIsNone(evaluate("frigate_monitoring_health", trigger))
        flag = "input_boolean.camera_health_binary_sensor_frigate_front_right_stream_healthy"
        self.assertIsNotNone(evaluate("frigate_monitoring_health", trigger, {flag: "on"}))
        trigger["id"] = "failure"
        self.assertIsNone(evaluate("frigate_monitoring_health", trigger, {flag: "on"}))
        self.assertIsNone(evaluate("frigate_monitoring_health", trigger))
        self.assertIsNotNone(evaluate("frigate_monitoring_health", trigger, {"binary_sensor.frigate_service_healthy": "on"}))

    def test_no_departure_from_lost_tracking(self):
        event = car(True, False, "end")
        event["payload_json"]["after"]["snapshot"] = None
        self.assertIsNone(evaluate("frigate_driveway_car_transitions", event))


unittest.main(argv=[sys.argv[0]])
