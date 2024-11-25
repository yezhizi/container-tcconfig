# this file is *not* meant to cover or endorse the use of nox or pytest or
# testing in general,
#
#  It's meant to show the use of:
#
#  - check-manifest
#     confirm items checked into vcs are in your sdist
#  - readme_renderer (when using a reStructuredText README)
#     confirms your long_description will render correctly on PyPI.
#
#  and also to help confirm pull requests to this project.

import nox
import os
import shutil
from pathlib import Path

# By default, sessions run with `nox -s lint`
nox.options.sessions = ["lint"]

TEST_DIR = "tests/"

# Define the minimal nox version required to run
nox.options.needs_version = ">= 2024.3.2"


def __test_pkg(session, pkg_path):
    session.install("pytest")
    session.install(pkg_path)
    session.run("py.test", TEST_DIR, *session.posargs)


@nox.session
def lint(session):
    session.install("ruff")
    session.run(
        "ruff",
        "check",
        "--exclude",
        ".nox,*.egg,build,data",
        "--select",
        "E,W,F",
        "--ignore",
        "F401",
        ".",
    )
    session.install("mypy")
    session.run("mypy", "src/", "--follow-imports=skip")


@nox.session
def build_and_check_dists(session):
    session.install("build", "check-manifest >= 0.42", "twine")
    # If your project uses README.rst, uncomment the following:
    # session.install("readme_renderer")

    session.run(
        "check-manifest",
        "--ignore",
        "noxfile.py,tests/**," "Makefile,requirements-dev.txt",
    )
    session.run("python", "-m", "build")
    session.run("python", "-m", "twine", "check", "dist/*")


@nox.session(python=["3.8", "3.9", "3.10", "3.11", "3.12"])
def build_and_tests(session):
    build_and_check_dists(session)

    generated_files = os.listdir("dist/")
    generated_sdist = os.path.join("dist/", generated_files[1])

    __test_pkg(session, generated_sdist)


@nox.session(python=["3.8", "3.9", "3.10", "3.11", "3.12"])
def tests(session):
    __test_pkg(session, ".")


@nox.session
def release(session):
    session.install("build", "twine")
    session.run("python", "-m", "build")
    session.run("python", "-m", "twine", "upload", "dist/*")


@nox.session
def clean(session):
    paths_to_clean = [
        "build",
        "dist",
        ".pytest_cache",
        "__pycache__",
        "*.pyc",
        "*.egg-info",
        ".coverage",
        ".mypy_cache",
    ]

    for path_str in paths_to_clean:
        for path in Path(".").rglob(path_str):
            if path.is_dir():
                shutil.rmtree(path, ignore_errors=True)
                session.log(f"Removed directory: {path}")
            elif path.is_file():
                path.unlink()
                session.log(f"Removed file: {path}")
    try:
        session.run("pip", "uninstall", "sample", "-y")
    except Exception:
        session.log("Uninstalled sample package")
