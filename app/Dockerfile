FROM python:3.12-slim

WORKDIR /app

# Crear usuario sin privilegios para cumplir políticas de seguridad de contenedores
RUN groupadd -r appgroup && useradd -r -g appgroup -u 10001 appuser

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .
RUN chown -R appuser:appgroup /app

USER 10001

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
