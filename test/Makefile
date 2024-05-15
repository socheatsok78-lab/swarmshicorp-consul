STACK_NAME := consul_test
make:
	@echo "make [deploy|remove|clean]"

deploy:
	docker stack deploy -c docker-compose.yml --detach=true --with-registry-auth $(STACK_NAME)

remove:
	docker stack rm $(STACK_NAME)

clean:
	@echo "Cleaning volumes..."
	@docker volume ls -q | grep consul- | xargs docker volume rm

reboot:
	@$(MAKE) remove || true
	@sleep 15
	@$(MAKE) deploy
