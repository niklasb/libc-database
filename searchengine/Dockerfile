FROM python:3.14-slim-bookworm AS gunicorn

ENV PYTHONUNBUFFERED 1
WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN pip install -r requirements.txt

COPY . /app

EXPOSE 8000

CMD gunicorn -k uvicorn.workers.UvicornWorker -b 0.0.0.0:8000 \
	--workers 4 --timeout 30 \
	--limit-request-line 262144 --limit-request-field_size 262144 \
	app:app
