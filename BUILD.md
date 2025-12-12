- Quick start

* mở terminal và gõ lệnh 'npm install' để render ra node_module
* tạo file .env cùng cấp với .env.local
* copy file .env.local sang .env
* mở terminal và gõ lệnh 'npm run dev' để chạy project
---

Các bước build lên VPS: Trên local:

- Đăng nhập GHCR (GitHub Container Registry)
  docker login ghcr.io -u YOUR_GITHUB_USERNAME -p YOUR_GITHUB_TOKEN

- Build: docker compose -f docker-compose.yml build
- Push lên GHCR và tạo image mới: docker push ghcr.io/YOUR_GITHUB_USERNAME/360home:latest

docker compose -f docker-compose.yml build && docker push ghcr.io/YOUR_GITHUB_USERNAME/360home:latest

Trên VPS (đang dùng user root): 
- Tạo thư mục và file cần thiết:
  mkdir -p /opt/360home
  cd /opt/360home

- Đăng nhập GHCR:
  echo YOUR_GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

- Tạo network (nếu chưa có):
  docker network create 360home

- Lần đẩy đầu tiên:
  docker pull ghcr.io/YOUR_GITHUB_USERNAME/360home:latest && docker run -d -p 3000:3000 --name 360home --network 360home ghcr.io/YOUR_GITHUB_USERNAME/360home:latest

- Pull image mới về: 
  docker pull ghcr.io/YOUR_GITHUB_USERNAME/360home:latest

- Xóa container cũ:
  docker stop 360home
  docker rm 360home

- Run app: 
  docker run -d -p 3000:3000 --name 360home --network 360home ghcr.io/YOUR_GITHUB_USERNAME/360home:latest

- Hoặc dùng docker-compose (khuyến nghị):
  cd /opt/360home
  docker-compose pull
  docker-compose up -d

- Lệnh nhanh (pull, stop, remove, run):
  docker pull ghcr.io/YOUR_GITHUB_USERNAME/360home:latest && docker stop 360home && docker rm 360home && docker run -d -p 3000:3000 --name 360home --network 360home ghcr.io/YOUR_GITHUB_USERNAME/360home:latest
 