# LiteRotation

Project scaffold created by manageProject.py.

The importable Python package is `LiteRotation/`. Install the project with
`pip install -e .` from the Conda environment defined in
`LiteRotationEnvironment.yml`. Logging uses the deployed `ompr.logUtils`; applications do not need OMPR installed.
The managed `ompr/` package is reserved for organiseMyProjects runtime helpers.
Use `from ompr.logUtils import getLogger, setApplication` in application code.

## Documentation

- [Architecture](documentation/architecture.md)
- [Deployed Runtime](documentation/runtimeDeployment.md)
- [Roadmap](project/roadmap.md)
- [Current Increment](project/currentIncrement.md)
- [Requirements](project/requirements/requirementsIndex.md)
- [Architecture Decisions](project/adr/adrIndex.md)
- [Release Guide](documentation/howToRelease.md)
- [Repository Layout](documentation/repositoryLayout.md)
- [Requirements Management](documentation/requirementsManagement.md)
- [Testing Process](documentation/testingProcess.md)
- [Agent Workflow](documentation/agentImplementationWorkflow.md)
- [Master Agent Instructions](.github/agent-instructions.md)
