FROM python:3.11-slim

# Create a non-root user for security
RUN groupadd --system app && useradd --system --gid app app

WORKDIR /app

# Install dependencies before copying source to leverage layer cache
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Hand ownership to the non-root user
RUN chown -R app:app /app
USER app

EXPOSE 5000

CMD ["python", "app.py"]
