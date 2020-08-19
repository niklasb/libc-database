FROM python:3.8-slim-buster AS uwsgi

ENV PYTHONUNBUFFERED 1
WORKDIR /app

RUN apt-get -y update && apt-get install -y gcc

COPY requirements.txt /app/requirements.txt
RUN pip install -r requirements.txt

COPY . /app

EXPOSE 8000

CMD uwsgi --ini uwsgi.ini
