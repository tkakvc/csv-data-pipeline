# ビルドコンテキストは backend/ ディレクトリを指定すること
# 例: docker build -f fargate_backfill/Dockerfile -t backfill-task backend/

FROM python:3.14-slim

WORKDIR /app

# ソースコードより先にrequirements.txtだけをコピー・インストールすることで、
# コードだけ変更した再ビルド時にpip installがキャッシュされ高速になる。
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY core/ ./core/
COPY fargate_backfill/main.py .

CMD ["python", "main.py"]
