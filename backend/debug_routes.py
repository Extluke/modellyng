from app.main import app
print("Length of app.routes:", len(app.routes))
for r in app.routes:
    print(getattr(r, 'path', r))
