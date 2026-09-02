.PHONY: run stop restart

# Examples:
#   make run
#   make run DEVICE=macos
#   make run ARGS='-d chrome --release'
run:
	./scripts/run_app.sh $(if $(DEVICE),-d "$(DEVICE)") $(ARGS)

# Clear stale Flutter / iOS debug tunnels (iproxy) and hung CoreDevice helpers.
stop:
	./scripts/stop_dev_app.sh

# Hard refresh the App attach path, then launch again.
restart: stop
	$(MAKE) run DEVICE="$(DEVICE)" ARGS="$(ARGS)"
