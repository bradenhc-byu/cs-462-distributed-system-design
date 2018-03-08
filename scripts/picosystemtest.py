#!/usr/bin/python3
import picosapi as picos
import time
import random

def mock_heartbeat(temperature):
	return { "genericThing":{"data":{"temperature":[{"temperatureF": float(format(temperature, '.2f'))}]}}}

def reset_pico_based_systems_test(manager_eci):
	print("Cleaning up from last test...")
	url = picos.event_url(manager_eci, "remove-sensor", "sensor", "unneeded_sensor")
	for i in range(1,6):
		print("Removing pico sensor %d" % i)
		ok, r = picos.post(url, data={"sensor_id": i})
		if not ok:
			print(r)
	return True

def run_pico_based_systems_test(manager_eci, reset=True):
	if reset:
		# Undo the last test
		reset_pico_based_systems_test(manager_eci)

	# Create 5 picos, generating a series of random heartbeats for each
	print("Generating 5 picos...")
	add_url = picos.event_url(manager_eci, "add-sensor", "sensor", "new_sensor")
	for i in range(1,6):
		ok, r = picos.post(add_url, data={"sensor_id": i})
		if not ok:
			print(r)
			return False
		eci = r.content["directives"][0]["options"]["pico"]["eci"]
		if eci is None:
			return False

		print("Populating %d with heartbeat data" % i)
		heartbeat_url = picos.event_url(eci, "mock-heartbeat", "wovyn", "heartbeat")
		for temp in range(10):
			ok, r = picos.post(heartbeat_url, data=mock_heartbeat(random.uniform(1.0, 70.0)))
			if not ok:
				print(r)
				return False

		print("Sending threshold violating heartbeat data to %d" % i)
		ok, r = picos.post(heartbeat_url, data=mock_heartbeat(100.0))
		if not ok:
			print(r)
			return False

	# Wait for a bit
	print("Check results!")
	time.sleep(10)


	# Delete a sensor pico
	print("Deleting sensor pico randomly...")
	remove_url = picos.event_url(manager_eci, "remove-sensor", "sensor", "unneeded_sensor")
	ok, r = picos.post(remove_url, data={"sensor_id": random.randint(1,5)})
	if not ok:
		print(r)
		return False

	# Wait for a bit
	print("Check results!")
	time.sleep(10)

	# Get the temperature values for all sensors with the sensor manager
	temperature_url = picos.api_url(manager_eci, "manage_sensors", "temperatures")
	ok, r = picos.get(temperature_url)
	print(r)



def main():
	# Testing
	run_pico_based_systems_test("3azLx2fE92qc7AcaJLQEof")
	return 0


if __name__ == "__main__":
	main()