# Windows 效能全開指令

## 一、電源計畫改為「高效能」或「終極效能」

在 **PowerShell（以系統管理員身分執行）** 貼上執行：

### 改為「高效能」
```powershell
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
```

### 改為「終極效能」（Windows 10 1803+，隱藏方案）
```powershell
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
```
執行後會顯示新方案 GUID，再執行：
```powershell
powercfg /setactive <剛顯示的 GUID>
```

或一行完成（複製整段）：
```powershell
$guid = (powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61) -replace '.*: (\S+)$','$1'; powercfg /setactive $guid
```

---

## 二、用高效能跑策略（不需管理員）

在 **一般 PowerShell** 執行，會先切到策略目錄並用較高優先順序跑：

```powershell
cd C:\Users\NEW\Downloads\trading_strategy_20260213_1620\tmp.ngY1UBeCDe
Start-Process python -ArgumentList "start_full_strategy.py" -Verb RunAs
```

若要以「高優先順序」在目前視窗跑（不開新視窗）：

```powershell
cd C:\Users\NEW\Downloads\trading_strategy_20260213_1620\tmp.ngY1UBeCDe
$p = Start-Process python -ArgumentList "start_full_strategy.py" -PassThru
$p.PriorityClass = 'High'
```

---

## 三、查詢目前電源計畫

```powershell
powercfg /getactivescheme
```

---

## 四、恢復「平衡」計畫

```powershell
powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
```
