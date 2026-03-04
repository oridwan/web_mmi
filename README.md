# MMI Lab Database Portal

This repository hosts the MMI lab website and database browser.

## Navigate the website

After starting the server, open `/` for the homepage.

Main routes:
- `/` - Lab homepage
- `/carbon_sp2` - LEGO-xtal sp2 carbon database
- `/electride` - Electride database entry
- `/electride/binary` - Binary electride dataset
- `/electride/ternary` - Ternary electride dataset

## Run locally

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Start server:
```bash
./start.sh
```

3. Open in browser:
- `http://localhost:5010/`

## Publish on Render

Create a Render Web Service with:
- Build Command: `pip install -r requirements.txt`
- Start Command: `./start.sh`

Then deploy from your GitHub repo branch.
