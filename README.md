# **Project Documentation: AI-Powered Call Agent with LLM and Database Integration**

## **Overview**
This project is an AI-powered call agent that:
1. Accepts user input (phone number, questions, and knowledge base).
2. Initiates a call with the user.
3. Uses a Large Language Model (LLM) to summarize the conversation.
4. Saves call transcripts, summaries, and user responses in a PostgreSQL database.
5. Provides an interface to download call records in Excel format.

## **Technologies Used**
- **Backend:** FastAPI
- **LLM Integration:** Ollama (Llama 3.1)
- **Database:** PostgreSQL (using `asyncpg`)
- **Containerization:** Docker & Docker Compose
- **PDF Processing:** PyMuPDF
- **Web Framework:** Jinja2 (for HTML rendering)
- **Environment Management:** Python-dotenv

---

# **1. Application Structure**

```
├── chatbot.py               # Main application logic
├── database.py              # Database connection functions
├── db_setup.sql             # Database schema
├── docker-compose.yml       # Defines services for the app and database
├── Dockerfile               # Docker configuration for the app
├── requirements.txt         # Python dependencies
├── templates/
│   ├── file_list.html       # Displays available call records
│   ├── prompt_generator2.html # UI for user input and generated prompts
└── .env                     # Stores environment variables (API keys, DB credentials)
```

---

# **2. Environment Configuration (`.env`)**
Store sensitive credentials like API keys and database details:

```plaintext
BLAND_API_KEY=yourapikey
POSTGRES_USER=myuser
POSTGRES_PASSWORD=mypassword
POSTGRES_DB=chatbot
POSTGRES_HOST=db
OLLAMA_HOST=localhost
```

---

# **3. Database Setup (`db_setup.sql`)**
Defines two tables:

- **`conversations`**: Stores call metadata.
- **`call_responses`**: Stores user responses to specific questions.

```sql
CREATE TABLE conversations (
    id SERIAL PRIMARY KEY,
    call_id TEXT UNIQUE NOT NULL,
    transcripts TEXT NOT NULL,
    summary TEXT,
    audio_url TEXT,
    phone_number TEXT
);

CREATE TABLE call_responses (
    id SERIAL PRIMARY KEY,
    call_id TEXT REFERENCES conversations(call_id),
    question TEXT NOT NULL,
    response TEXT NOT NULL
);
```

---

# **4. Backend Implementation (`chatbot.py`)**

## **4.1 FastAPI Setup**
```python
from fastapi import FastAPI, Form, Request
from fastapi.templating import Jinja2Templates
from database import get_db_connection
import requests
import fitz
import os
from dotenv import load_dotenv
import tempfile
from ollama import Client
```
- **FastAPI** is used to build the web API.
- **Jinja2Templates** is used for rendering HTML pages.
- **Ollama** connects to the LLM for text generation.
- **dotenv** loads environment variables.

### **Initialize App and LLM Client**
```python
app = FastAPI()
templates = Jinja2Templates(directory="templates")
ollama_client = Client(host='http://localhost:11434')
load_dotenv()
api_key = os.getenv("BLAND_API_KEY")
```
- Defines a FastAPI instance.
- Loads `.env` variables for secure key storage.

---

## **4.2 PDF Handling**
### **Download PDF from URL**
```python
def download_pdf(pdf_url, save_path="downloaded.pdf"):
    response = requests.get(pdf_url, stream=True)
    if response.status_code == 200:
        with open(save_path, "wb") as pdf_file:
            pdf_file.write(response.content)
        return save_path
    else:
        raise Exception(f"Failed to download PDF. Status code: {response.status_code}")
```
- Fetches the knowledge base in PDF format.
- Saves it locally for text extraction.

### **Extract Text from PDF**
```python
def extract_text_blocks(pdf_path):
    doc = fitz.open(pdf_path)
    text = ""
    for page in doc:
        blocks = page.get_text("blocks")
        blocks.sort(key=lambda b: (b[1], b[0])) 
        for block in blocks:
            text += block[4] + "\n"
    return text.strip()
```
- Extracts text from PDFs in a structured order.

---

## **4.3 Generate AI Prompt**
### **User Input Page**
```python
@app.get("/")
async def home(request: Request):
    return templates.TemplateResponse("prompt_generator2.html", {"request": request})
```
- Renders the UI for input collection.

### **Generate a Call Prompt**
```python
@app.post("/generate_prompt")
async def generate_prompt(request: Request, knowledge_base_url: str = Form(...),
                          phone_number: str = Form(...), questions: str = Form(...),
                          call_output: str = Form(...), suggestions: str = Form(...)):
    
    question_list = questions.split('\n')
    generation_input = f"""
        questions:{question_list}
        Call Output: {call_output}
        Suggestions: {suggestions}
        # Instructions #
        Generate a 150+ word prompt based on the call details.
    """
    
    def prompt_generator(user_message: str):
        response = ollama_client.chat(
            model="llama3.1:latest",
            messages=[{'role': 'user', 'content': user_message}]
        )
        return response.get('message', {}).get('content', "No response")

    generated_prompt = prompt_generator(generation_input)

    return templates.TemplateResponse("prompt_generator2.html", {
         "request": request, "generated_prompt": generated_prompt,
         "phone_number": phone_number, "knowledge_base_url": knowledge_base_url,
         "questions": questions, "call_output": call_output, "suggestions": suggestions
    })
```
- Generates a structured call prompt based on input.
- Calls LLM (Llama 3.1) to create a call script.

---

## **4.4 Call Execution**
```python
@app.post("/make_call")
async def make_call(request: Request, phone_number: str = Form(...),
                    knowledge_base_url: str = Form(...), final_prompt: str = Form(...),
                    questions: str = Form(...)):
    
    pdf_path = download_pdf(knowledge_base_url)
    formatted_text = extract_text_blocks(pdf_path)
    os.remove(pdf_path)
    
    prompter = f"""
    Your knowledge base: {formatted_text}.
    Instructions:
    - Use ONLY the provided knowledge.
    - Never infer missing details.
    - Follow the structured script: {final_prompt}
    """
    
    data = {
        'phone_number': phone_number,
        'task': f"Call user and strictly follow script {final_prompt}",
        'prompt': prompter,
        'webhook': 'your_url/webhook',
        'record': True, 'reduce_latency': True, 'amd': True, 'model': 'base'
    }

    response = requests.post('https://api.bland.ai/v1/calls', json=data, headers={'authorization': api_key})
    
    return {"message": "Call initiated", "call_id": response.json().get('call_id')}
```
- Calls Bland API to initiate the call.
- Uses the generated prompt.
- Replace  'webhook': 'your_url/webhook', with your url which is of https format

---

## **4.5 Webhook Handling**
```python
@app.post("/webhook")
async def webhook(data: WebhookData):
    call_id = data.call_id
    transcripts = "\n".join([t.text for t in data.transcripts])
    summary = query_gemini(transcripts)
    audio_url = f"https://api.bland.ai/v1/calls/{call_id}/recording"

    await save_conversation(call_id, transcripts, summary, audio_url, data.to)
```
- Stores the call summary and user responses in the database.

---

## **4.6 File Download**
```python
@app.get("/download/{call_id}")
async def download_file(call_id: str):
    conn = await get_db_connection()
    responses = await conn.fetch("SELECT question, response FROM call_responses WHERE call_id = $1", call_id)
    summary = await conn.fetchval("SELECT summary FROM conversations WHERE call_id = $1", call_id)
    
    wb = Workbook()
    ws = wb.active
    ws.append(["Question", "Response"])
    for row in responses:
        ws.append([row['question'], row['response']])
    ws.append(["Summary", summary])

    excel_stream = BytesIO()
    wb.save(excel_stream)
    excel_stream.seek(0)
    
    return StreamingResponse(excel_stream, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                             headers={"Content-Disposition": f"attachment; filename={call_id}.xlsx"})
```
- Generates and downloads an Excel report of the call.

---
# **HTML Code Explanation**

The project includes **two HTML templates**:
1. **`file_list.html`** – Displays available call records and allows users to download call data in Excel format.
2. **`prompt_generator2.html`** – Provides an interface to generate prompts, make calls, and display results.

---

## **1. File: `file_list.html`**
### **Purpose**  
This HTML file displays a list of available call records and provides download links for their corresponding Excel files.

---

### **Code Explanation**
```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Available Call Records</title>
</head>
<body>
    <h2>Available Call Records</h2>
    <ul>
        {% for call_id in files %}
            <li>
                Call ID: {{ call_id }}
                <a href="/download/{{ call_id }}" download>
                    <button>Download Excel</button>
                </a>
            </li>
        {% endfor %}
    </ul>
</body>
</html>
```

### **Key Components**
| **Tag** | **Explanation** |
|---------|----------------|
| `<!DOCTYPE html>` | Declares the document type as HTML5. |
| `<html lang="en">` | Specifies the language as English. |
| `<head>` | Contains metadata like character encoding and title. |
| `<meta charset="UTF-8">` | Supports special characters in different languages. |
| `<meta name="viewport" content="width=device-width, initial-scale=1.0">` | Ensures mobile responsiveness. |
| `<title>Available Call Records</title>` | Sets the title of the webpage. |
| `<h2>Available Call Records</h2>` | Displays the main heading. |
| `<ul>` | Creates an unordered list of call records. |
| `{% for call_id in files %}` | **Jinja2 loop:** Iterates over available `call_id` values from the backend. |
| `<li>` | Represents an individual call record. |
| `{{ call_id }}` | Displays the call ID dynamically. |
| `<a href="/download/{{ call_id }}" download>` | Generates a **download link** for the Excel file associated with the call ID. |
| `<button>Download Excel</button>` | Provides a button to download the Excel file. |
| `{% endfor %}` | Ends the Jinja2 loop. |

### **Functionality**
- Loops through `files` (list of call IDs) sent from the FastAPI backend.
- Displays each call ID.
- Provides a **download button** to retrieve the corresponding call data in **Excel format**.

---

## **2. File: `prompt_generator2.html`**
### **Purpose**  
This HTML file provides an input form where users can:
- Enter **phone number, knowledge base URL, and questions**.
- View **generated AI prompts**.
- Initiate a call using the generated prompt.

---

### **Code Explanation**
```html
<!DOCTYPE html>
<html>
<head>
    <title>Prompt Generator</title>
</head>
<body>
    <form method="post" action="/generate_prompt">
        <h3>Call Details:</h3>
        <input type="text" name="phone_number" placeholder="Phone Number" required value="{{ phone_number }}">
        <input type="text" name="knowledge_base_url" placeholder="Knowledge Base URL" required value="{{ knowledge_base_url }}">
        <textarea name="questions" placeholder="Questions (one per line)">{{ questions }}</textarea>

        <h3>Call Output:</h3>
        <textarea name="call_output" rows="4" cols="50">{{ call_output }}</textarea>

        <h3>Suggestions:</h3>
        <textarea name="suggestions" rows="4" cols="50">{{ suggestions }}</textarea>

        <input type="submit" value="Generate Prompt">
    </form>
```

### **Key Components**
| **Tag** | **Explanation** |
|---------|----------------|
| `<form method="post" action="/generate_prompt">` | Submits data to the `/generate_prompt` route using the **POST** method. |
| `<input type="text" name="phone_number" required>` | Field for entering the **phone number**. |
| `<input type="text" name="knowledge_base_url" required>` | Field for entering the **knowledge base URL**. |
| `<textarea name="questions">` | Field for **entering questions** to be asked in the call. |
| `<textarea name="call_output">` | Displays **call output** (if available). |
| `<textarea name="suggestions">` | Displays **suggestions** (if available). |
| `<input type="submit" value="Generate Prompt">` | Submits the form. |

---

### **Displaying the Generated Prompt**
```html
    {% if generated_prompt %}
    <form method="post" action="/make_call">
        <h3>Generated Prompt:</h3>
        <textarea name="final_prompt" rows="8" cols="80">{{ generated_prompt }}</textarea>

        <h3>Call Details:</h3>
        <input type="hidden" name="phone_number" value="{{ phone_number }}">
        <input type="hidden" name="knowledge_base_url" value="{{ knowledge_base_url }}">
        <input type="hidden" name="questions" value="{{ questions }}">

        <p><strong>Phone Number:</strong> {{ phone_number }}</p>
        <p><strong>Knowledge Base URL:</strong> {{ knowledge_base_url }}</p>
        <p><strong>Questions:</strong><br>{{ questions | replace('\n', '<br>') | safe }}</p>

        <input type="submit" value="Make Call">
    </form>
    {% endif %}
```

### **Key Components**
| **Tag** | **Explanation** |
|---------|----------------|
| `{% if generated_prompt %}` | **Checks if a prompt was generated.** If `generated_prompt` is available, this section is displayed. |
| `<form method="post" action="/make_call">` | Submits the final **generated prompt** to the `/make_call` route. |
| `<textarea name="final_prompt">{{ generated_prompt }}</textarea>` | Displays the **generated AI prompt**. |
| `<input type="hidden" name="phone_number" value="{{ phone_number }}">` | Passes the **phone number** (hidden field). |
| `<input type="submit" value="Make Call">` | Sends the generated prompt to **initiate a call**. |

---

## **How These Templates Work Together**
1. **User visits the app** → `prompt_generator2.html` is displayed.
2. **User fills in details** and submits the form.
3. **Backend processes input** and generates an AI prompt.
4. **Generated prompt appears** in the form.
5. **User clicks "Make Call"** → Call is initiated using the generated script.
6. **Backend saves conversation details** in the database.
7. **User can download call records** from `file_list.html`.

---

## **Conclusion**
These HTML templates **integrate seamlessly with FastAPI and Jinja2** to provide:
- A dynamic UI for generating and managing AI-powered calls.
- A downloadable database of call records for analysis.


---
# **Dockerfile and Docker Compose Documentation**

## **1. Dockerfile**
The **Dockerfile** is responsible for creating a Docker container that runs the AI-powered call agent. It installs all necessary dependencies and sets up the environment for running FastAPI, PostgreSQL, and the AI model (Ollama with Llama 3.1).

### **Dockerfile Breakdown**
```dockerfile
FROM nvidia/cuda:12.2.0-runtime-ubuntu22.04
```
- **Base Image:** Uses the official NVIDIA CUDA 12.2 runtime on Ubuntu 22.04.
- This allows GPU acceleration for LLM processing.

```dockerfile
ENV DEBIAN_FRONTEND=noninteractive
```
- **Disables interactive prompts** when installing packages.

```dockerfile
RUN apt-get update && apt-get install -y \
    curl gnupg ca-certificates build-essential gcc postgresql-client python3 python3-pip python3-venv && \
    rm -rf /var/lib/apt/lists/*
```
- **Installs system dependencies:**
  - `curl, gnupg, ca-certificates`: Required for package management and security.
  - `build-essential, gcc`: Needed for compiling Python packages.
  - `postgresql-client`: Required for interacting with PostgreSQL.
  - `python3, python3-pip, python3-venv`: Python and its package manager.

```dockerfile
RUN apt-get update && apt-get install -y nvidia-container-toolkit && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
```
- **Installs NVIDIA Container Toolkit** for GPU acceleration inside the container.

```dockerfile
RUN curl -fsSL https://ollama.com/install.sh | bash && \
    echo 'export PATH=$PATH:/root/.ollama/bin' >> ~/.bashrc && \
    . ~/.bashrc  
```
- **Installs Ollama (LLM Framework)**
- **Updates PATH** to include Ollama binaries.

```dockerfile
WORKDIR /app
```
- **Sets the working directory** to `/app` inside the container.

```dockerfile
COPY requirements.txt .
```
- **Copies `requirements.txt`** into the container.

```dockerfile
RUN pip install --no-cache-dir -r requirements.txt
```
- **Installs Python dependencies** from `requirements.txt`.

```dockerfile
COPY . .
COPY .env /app/.env
```
- **Copies all project files** into the container.
- **Copies `.env` file** to `/app/.env` for environment configuration.

```dockerfile
RUN echo "export $(cat /app/.env | xargs)" >> /root/.bashrc
```
- **Exports environment variables** for runtime execution.

```dockerfile
EXPOSE 8000
```
- **Exposes port `8000`** for the FastAPI application.

### **Entry Point Script**
```dockerfile
CMD sh -c 'echo "Waiting for PostgreSQL to be ready..." && \
until PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1" > /dev/null 2>&1; do \
echo "Waiting for database..."; sleep 2; done; \
echo "Database is ready. Running db_setup.sql..." && \
PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -f /app/db_setup.sql && \
echo "db_setup.sql executed successfully!" && \
OLLAMA_CUDA=1 ollama serve & \
while ! ollama list | grep -q "llama3.1"; do \
echo "Downloading Llama 3.1..."; ollama pull llama3.1; sleep 2; done; \
uvicorn chatbot:app --host 0.0.0.0 --port 8000 --reload'
```
- **Ensures PostgreSQL is ready before starting the application.**
- **Runs database initialization script (`db_setup.sql`).**
- **Starts Ollama LLM service and downloads `llama3.1` model if not available.**
- **Launches the FastAPI app using Uvicorn.**

---

## **2. Docker Compose (`docker-compose.yml`)**
The **Docker Compose** file defines multiple services and their configurations.

### **Services Defined**
1. **`db`** (PostgreSQL Database)
2. **`app`** (FastAPI Application)

### **Docker Compose Breakdown**
```yaml
version: "3.8"
```
- Specifies **Docker Compose version**.

```yaml
networks:
  samajhai_network:
    driver: bridge
```
- Defines a **custom network** for inter-service communication.

---

### **Database Service (`db`)**
```yaml
services:
  db:
    image: ankane/pgvector
    container_name: chatbot_db
    restart: always
    environment:
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypassword
      POSTGRES_DB: chatbot
    ports:
      - "5432:5432"
    networks:
      - samajhai_network
    volumes:
      - chatbot_data:/var/lib/postgresql/data
      - ./db_setup.sql:/docker-entrypoint-initdb.d/db_setup.sql
    command: [ "postgres", "-c", "shared_preload_libraries=vector" ]
```
- Uses **`pgvector`** (PostgreSQL with vector support for AI models).
- Stores **credentials in environment variables**.
- Maps **host port `5432` to container port `5432`**.
- Mounts a **volume for persistent database storage**.
- Runs PostgreSQL **with vector support**.

---

### **Application Service (`app`)**
```yaml
  app:
    build: .
    container_name: chatbot_app
    restart: always
    depends_on:
      - db
    ports:
      - "8000:8000"
    networks:
      - samajhai_network
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [ gpu ]
    environment:
      BLAND_API_KEY: ${BLAND_API_KEY}
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypassword
      POSTGRES_DB: chatbot
      POSTGRES_HOST: db
      OLLAMA_HOST: localhost
    volumes:
      - .:/app
```
- **Builds the image from `Dockerfile`.**
- **Depends on `db`** (database must start first).
- Maps **port `8000`** to expose FastAPI.
- Uses the **custom network (`samajhai_network`)**.
- **Allocates GPU resources** (`nvidia` driver).
- **Passes environment variables** to the container.

---

### **Volumes Section**
```yaml
volumes:
  chatbot_data:
  ollama_data:
```
- **Persistent storage** for the database (`chatbot_data`).
- **Persistent storage** for LLM model downloads (`ollama_data`).

---

## **3. Running the Application with Docker**
### **Step 1: Build and Start Services**
Run the following command to build and start the containers:
```bash
docker-compose up --build
```
- **`--build`** ensures images are rebuilt before starting.

### **Step 2: Running in Detached Mode**
To run in the background:
```bash
docker-compose up -d
```

### **Step 3: Viewing Logs**
Check logs of the application:
```bash
docker-compose logs -f app
```

### **Step 4: Stopping the Containers**
Stop all running services:
```bash
docker-compose down
```

---

# **Steps to Generate an Ngrok Link for Your FastAPI Application**

Ngrok allows you to expose your **localhost server** to the internet by creating a temporary public URL. This is useful for testing **webhooks** or accessing your FastAPI application remotely.

---

## **1. Install Ngrok**
If you haven't installed Ngrok yet, you can download and install it using the following steps:

### **Windows**
1. Download **Ngrok** from: [https://ngrok.com/download](https://ngrok.com/download)
2. Extract the ZIP file.
3. Open **Command Prompt** in the extracted folder.
4. Run:
   ```sh
   ngrok.exe authtoken YOUR_AUTH_TOKEN
   ```

### **Linux / macOS**
Run the following commands in your terminal:
```sh
wget https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip
unzip ngrok-stable-linux-amd64.zip
sudo mv ngrok /usr/local/bin
```
Now, authenticate with your Ngrok account:
```sh
ngrok authtoken YOUR_AUTH_TOKEN
```
You can get your **Auth Token** from [Ngrok Dashboard](https://dashboard.ngrok.com/get-started/setup).

---

## **2. Start Your FastAPI Server**
First, ensure your FastAPI application is running on **port 8000**:
```sh
uvicorn chatbot:app --host 0.0.0.0 --port 8000 --reload
```
Or, if running inside Docker:
```sh
docker-compose up
```

---

## **3. Start Ngrok**
Run the following command in command prompt in the file location of ngrok.exe to expose port `8000`:
```sh
ngrok http 8000
```

If you need **HTTPS**, use:
```sh
ngrok http https://localhost:8000
```

---

## **4. Get the Public URL**
After running the command, you'll see an output similar to:
```
ngrok by @inconshreveable                                       
Session Status                online
Account                       YourNgrokAccount
Version                       2.3.35
Region                        United States (us)
Web Interface                 http://127.0.0.1:4040
Forwarding                    http://xyz123.ngrok.io -> http://localhost:8000
Forwarding                    https://xyz123.ngrok.io -> http://localhost:8000
```
The **`Forwarding`** URLs are your **public access links**.

Example:
- **HTTP:** `http://xyz123.ngrok.io`
- **HTTPS:** `https://xyz123.ngrok.io`

---

## **5. Use the Ngrok Link for Webhooks**
Update your webhook URL in `chatbot.py`:
```python
'webhook': 'https://xyz123.ngrok.io/webhook'
```

This ensures the AI call service can send webhook responses to your FastAPI application.Because Bland AI only accepts data from https servers only.


##   Restart the App Container after webhook replacement(Fastest way)
in bash run:
```
docker restart chatbot_app

```
- This will **restart only the app container** without stopping the database (`db`).



---



## **6. Stop Ngrok**
To stop the Ngrok session, press **CTRL + C** or run:
```sh
killall ngrok
```
On Windows, close the **Command Prompt** window.

---

### **List of Commands**
| Step | Command |
|------|---------|
| **Authorize Ngrok** | `ngrok authtoken YOUR_AUTH_TOKEN` |
| **Start FastAPI** | `docker-compose up` |
| **Expose FastAPI to the Internet** | `ngrok http 8000` |
| **Find Public URL** | Output in the terminal (`https://xyz123.ngrok.io`) |
| **Use for Webhooks** | Update FastAPI webhook URL |
| **Stop Ngrok** | `CTRL + C` or `killall ngrok` |

Now, your FastAPI application is accessible from anywhere using the Ngrok link.



---  

  

*"Thank you Sir for this wonderful opportunity. We deeply appreciate the trust and encouragement extended to me."*  

**With regards,**  
**Nevil Jeesan**  

