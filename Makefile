.PHONY: setup lint format test diagram clean

setup:
	uv sync
	uv run pre-commit install

lint:
	uv run ruff check .

format:
	uv run ruff format .

test:
	uv run pytest -q

diagram:
	npx -y @mermaid-js/mermaid-cli -i docs/architecture/fuelflow-architecture.mmd -o docs/architecture/fuelflow-architecture.png -b transparent

clean:
	rm -rf .ruff_cache .pytest_cache
