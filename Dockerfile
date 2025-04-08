
FROM nvidia/cuda:12.2.0-runtime-ubuntu22.04


ENV DEBIAN_FRONTEND=noninteractive


RUN apt-get update && apt-get install -y \
    curl gnupg ca-certificates build-essential gcc postgresql-client python3 python3-pip python3-venv && \
    rm -rf /var/lib/apt/lists/*


RUN apt-get update && apt-get install -y nvidia-container-toolkit && \
    apt-get clean && rm -rf /var/lib/apt/lists/*


RUN curl -fsSL https://ollama.com/install.sh | bash && \
    echo 'export PATH=$PATH:/root/.ollama/bin' >> ~/.bashrc && \
    . ~/.bashrc  # 🔥 **FIXED: Replaced `source ~/.bashrc` with `. ~/.bashrc`**




WORKDIR /app


COPY requirements.txt .


RUN pip install --no-cache-dir -r requirements.txt


COPY . .


COPY .env /app/.env


RUN echo "export $(cat /app/.env | xargs)" >> /root/.bashrc




EXPOSE 8000

CMD sh -c 'echo "Waiting for PostgreSQL to be ready..." && until PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1" > /dev/null 2>&1; do echo "Waiting for database..."; sleep 2; done; echo "Database is ready. Running db_setup.sql..." && PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -f /app/db_setup.sql && echo "db_setup.sql executed successfully!" && OLLAMA_CUDA=1 ollama serve & while ! ollama list | grep -q "llama3.1"; do echo "Downloading Llama 3.1..."; ollama pull llama3.1; sleep 2; done; uvicorn chatbot:app --host 0.0.0.0 --port 8000 --reload'