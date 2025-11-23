# Spotify setup in 5 minutes

This project needs a Spotify application (Client ID + Secret) and a Redirect URI that matches your deployed URL.

## 1) Create a Spotify app

- Go to https://developer.spotify.com/dashboard
- Log in and click "Create app"
- Name: any (e.g., playlistparser)
- Description: anything short
- Redirect URI:
  - Local dev: `http://127.0.0.1:3000/auth/callback`
  - Terraform deploy (staging/prod): use the value from `terraform output spotify_redirect_uri` (looks like `http://<alb-dns>/api/auth/callback`)
- Save

Copy these values from the app page:
- Client ID
- Client Secret

## 2) Put values in Terraform tfvars

Open your environment tfvars (e.g., `terraform/environments/staging/staging.tfvars`):

```
spotify_client_id     = "<YOUR_CLIENT_ID>"
spotify_client_secret = "<YOUR_CLIENT_SECRET>"
spotify_redirect_uri  = "http://<alb-dns>/api/auth/callback"
```

Tip: You can copy the exact redirect from Terraform output after apply:

```
terraform output spotify_redirect_uri
```

## 3) Apply Terraform

- From the environment folder:

```
terraform plan -var-file=staging.tfvars
terraform apply -var-file=staging.tfvars
```

## 4) Test login

- Open the frontend URL (Terraform output `frontend_base_url`)
- Click "Login with Spotify"
- Approve → you should be redirected back to `/api/auth/callback` and be logged in

## Troubleshooting

- "Redirect URI mismatch": The URI in Spotify dashboard doesn’t match exactly. Fix host, scheme (http/https), and path.
- 400 on callback: Check that `SPOTIFY_CLIENT_ID/SECRET/REDIRECT_URI` are set on the API instances (they come from Terraform launch template env).
- Using HTTPS: For production, add ACM certificate + ALB HTTPS listener and then change `spotify_redirect_uri` to `https://<domain>/api/auth/callback` in both Spotify dashboard and tfvars.
