.PHONY: run stop restart

run:
	./scripts/run_app.sh

# Clear stale Flutter / iOS debug tunnels (iproxy) and hung CoreDevice helpers.
stop:
	./scripts/stop_dev_app.sh

# Hard refresh the App attach path, then launch again.
restart: stop
	$(MAKE) run
