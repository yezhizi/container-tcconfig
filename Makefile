refresh: clean build install lint

build:
	python -m build	

install: 
	pip install .	

build_dist:
	make clean
	python -m build
	pip install dist/*.whl
	make test

release:
	python -m twine upload dist/*

lint:
	flake8 src/ tests/ --count --max-line-length=127 --ignore=W503
	mypy src/ --follow-imports=skip

test:
	python -m unittest

clean:
	rm -rf __pycache__
	rm -rf tests/__pycache__
	find src/ -name "__pycache__" -type d -exec rm -rf "{}" +
	find src/ -name "*.egg-info" -type d -exec rm -rf "{}" +
	rm -rf build
	rm -rf dist
	rm -rf "*.egg-info" 
	rm -rf .pytest_cache
	rm -rf .mypy_cache
	pip uninstall -y sample || true