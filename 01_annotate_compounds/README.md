# Environment management

We use uv as a Python package manager. The environment for this module is called pesticides. To install and activate the environment:

```bash
# Create the uv environment (only needed the first time)
uv venv --python=3.12 pesticides
python -m ipykernel install --user --name=pesticides --display-name "Python (pesticides)"

# Activate the environment
source pesticides/bin/activate

# Install dependencies
uv pip install -r requirements.txt
```

To update the requirements.txt, run:

```bash
poetry export --without-hashes --format=requirements.txt > requirements.txt
```
