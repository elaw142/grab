FROM python:3.11-slim

RUN apt-get update && apt-get install -y ffmpeg nodejs npm && rm -rf /var/lib/apt/lists/*

RUN npm install -g @yt-dlp/ejs

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

CMD ["python", "app.py"]