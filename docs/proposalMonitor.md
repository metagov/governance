# Proposal monitor UI
Monitors the core and treasury governors for new proposals, then tracks them through each of their stages.

The UI has two components:
1. Proposal Monitor CLI - this is a long running service that generates a json file of proposal events
2. propMonUI.html - a basic UI that displays the json file generated by the proposal monitor service

Note: You can run via ts-node installed globally, or compile with tsc and run with node.

To run both components together:
```
yarn
yarn build
ETH_RPC=<your ethereum rpc here> yarn propmon
```

Then navigate to `localhost:8080/propMonUi/propMonUi.html` in a browser. You will need to wait around 30 seconds whilst the propmon discovers all proposals and their stages. The propmon creates a proposalStage.json file that contains a json representation of the data you see on the web page.

## Running with docker
```
docker build -t propmon -f propMon.Dockerfile .
docker run -p 8080:8080 -e ETH_RPC=<your ethereum rpc here> propmon
```
Navigate to `localhost:8080/propMonUi/propMonUi.html`