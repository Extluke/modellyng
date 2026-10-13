  ```powershell
  cd "d:\DF\F\faqiih\code\mobile app\modellyng"

  docker compose up -d

  ```
  ```powershell
  cd "d:\DF\F\faqiih\code\mobile app\modellyng"

  supabase start

  ```
  ```powershell
  cd "d:\DF\F\faqiih\code\mobile app\modellyng\backend"

  .\.venv\Scripts\Activate.ps1

  python -m uvicorn app.main:app --reload --port 8000

  ```
  ```powershell
  cd "d:\DF\F\faqiih\code\mobile app\modellyng\backend"
  
  .\.venv\Scripts\Activate.ps1

  python -m celery -A app.celery_app:celery_app worker --pool=solo --loglevel=INFO

  ```
  ```powershell
  cd "d:\DF\F\faqiih\code\mobile app\modellyng\frontend"

  flutter run -d web-server --web-port 3000
  
  ```