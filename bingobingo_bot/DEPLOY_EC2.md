# 將 bingobingo_bot 部署到 EC2（openclaw 同機）

## 方式一：本機用 SCP 上傳（Windows PowerShell）

請先將下面變數改成你的 EC2 資訊：

- `EC2_HOST`：EC2 的 Public DNS 或 IP（例：`ec2-xx-xx-xx-xx.compute-1.amazonaws.com`）
- `EC2_USER`：登入帳號（Ubuntu 用 `ubuntu`，Amazon Linux 用 `ec2-user`）
- `KEY_PATH`：你存 `.pem` 金鑰的本機路徑

在 **專案根目錄** `c:\src\anya_trade_app` 執行：

```powershell
$EC2_HOST = "你的EC2主機名或IP"
$EC2_USER = "ubuntu"
$KEY_PATH = "C:\path\to\your-key.pem"

scp -i $KEY_PATH -r bingobingo_bot ${EC2_USER}@${EC2_HOST}:~/
```

上傳後，bot 會在 EC2 的 **`~/bingobingo_bot`**。

---

## 方式二：在 EC2 上用 Git 拉取

若 EC2 已能連 GitHub（或你願意在 EC2 設 SSH key）：

```bash
# SSH 登入 EC2 後
cd ~
git clone https://github.com/Trader-Wei/Trade-Mission.git
# 或若已有 repo，只更新：
# cd Trade-Mission && git pull origin main
```

bot 會在 **`~/Trade-Mission/bingobingo_bot`**。

---

## 在 EC2 上提供賓果網頁

若要在 EC2 用網址開賓果頁（例如 `http://你的EC2/bingobingo/`），可任選一種：

### A. 用 Python 靜態伺服器（最簡單）

```bash
cd ~/bingobingo_bot/web
python3 -m http.server 8080
```

然後用 **http://EC2的IP:8080** 開。若要常駐，可用 `nohup` 或 systemd。

### B. 用 Nginx 代管（對外 80/443）

1. 安裝 nginx：`sudo apt install nginx`
2. 建立設定（例：`/etc/nginx/sites-available/bingobingo`）：

```nginx
server {
    listen 80;
    server_name _;   # 或你的網域
    root /home/ubuntu/bingobingo_bot/web;   # 改成實際路徑
    index index.html;
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

3. 啟用並重載：

```bash
sudo ln -s /etc/nginx/sites-available/bingobingo /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

---

## 只跑 Python 預測（指令列）

SSH 進 EC2 後：

```bash
cd ~/bingobingo_bot
pip3 install -r requirements.txt
python3 -m bingobingo_bot.run_bot --top 3
# 或從 CSV 跑：python3 -m bingobingo_bot.run_bot --csv /path/to/history.csv --top 3
```

（若專案在 `~/Trade-Mission`，請先 `cd ~/Trade-Mission` 再執行上述指令。）
