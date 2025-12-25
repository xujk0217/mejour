# mejour

以 SwiftUI 打造的地圖筆記 App，透過登入後可在地圖上紀錄/瀏覽地點日誌，並與好友或社群分享。主要特色是玻璃質感 UI、地點去重與 Apple POI 候選、以及照片 EXIF 取點與拍攝時間的便利貼文流程。

## 主要功能
- 地圖分頁：個人 / 朋友 / 社群三個分頁，顯示我的地點、追蹤好友的足跡與公開地點。
- 地點頁：依模式切換顯示公開貼文、僅我的貼文或指定好友的貼文；支援編輯地點（社群模式）。
- 新增日誌：可從 EXIF 或定位抓取座標與拍攝時間，選取附近地點或建立新地點，新增照片、公開/私人選擇與標籤。
- 隨機貼文：社群分頁可抽取附近地點貼文，左右滑動 like/dislike 並跳回地圖對應地點。
- 好友：輸入 userId 追蹤、查看好友列表、在地圖上以頭像顯示好友曾發文的地點。
- 登入/註冊：內建登入覆蓋畫面與設定頁，提供預設帳號登入與註冊新帳號，Token 登入後自動載入資料。

## 專案結構
- `View/RootMapView.swift`：主地圖與分頁、搜尋、隨機貼文、Sheet 路由。
- `View/PostView/AddLogWizard.swift`：新增日誌流程、EXIF 解析、地點候選/建立與貼文送出。
- `View/SheetView/PlaceSheetView.swift`：地點資訊與貼文列表。
- `View/LoginOverlayView.swift`、`View/SheetView/ProfileSheetView 2.swift`：登入/註冊與個人頁/設定。
- `Manager/`：`AuthManager`、`PlacesManager`、`PostsManager` 對應登入/地點/貼文 API。
- `ViewModel/MapViewModel.swift`：地圖狀態、地點/貼文快取、定位與 dedup/鄰近搜尋。
- `Models/`：資料模型、追蹤好友 `FollowStore`、`PostContent` 標籤/時間編碼、`MultipartFormData`。
- `Utils/`、`UI/`：快取圖片、按鈕樣式與玻璃/流光效果。

## 開發與執行
1. 開啟專案：`open mejour.xcodeproj`（Target：`mejour`）。
2. Xcode 15+、iOS 17+（MapCameraPosition 綁定版 MapKit）模擬器或實機；設定 Team 以通過簽章。
3. 權限：定位（顯示自身位置/搜尋附近地點）、照片（上傳照片 + EXIF 讀取）。
4. 後端：`https://meejing-backend.vercel.app`。預設登入帳號 `test / 12345678`，或在登入覆蓋畫面/設定頁註冊新帳號。
5. 朋友預設有幾個假資料 userId（10–13）；可在好友列表中新增/移除。

## 資料流與快取
- `MapViewModel` 會以登入狀態載入地點，並以 UUID/座標去重；維護我的/社群地點、貼文、好友貼文快取（預設 5 分鐘）。
- `AddLogWizard` 會將照片拍攝時間與標籤編碼進貼文內容，建立貼文後同步更新地點與各種快取。
- `PlacesManager` / `PostsManager` / `AuthManager` 皆使用 Bearer Token；失效時會顯示錯誤並清空部分快取。

## 開發備忘
- 若後端 by-place 回傳單筆或陣列皆可解析（`PostsManager.decodeObjectOrArray`）。
- Apple POI（未入庫）會在發文時自動建立成正式地點並去重。
- 目前「愛心/收藏」頁籤尚無後端 API，維持空列表；可依需要補 API 後串接。
