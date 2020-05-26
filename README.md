<<<<<<< HEAD
This repository contains two deployments systems on deploying interactive applications, using the Cube Analysis and Rendering Tool for Astronomy (CARTA) as the use case. We compare the use of Kubernetes as an orchestration framework and Slurm as a resource manager in HPC environment. The objective is to find the best deployment system for interactive applications. For each deployment method we going to list the scripts that needs to be executed. Below is the technical overview of CARTA deployed on both Kubernetes and on HPC using Slurm as a resource manager. 

TECHNICAL OVERVIEW

![Uploading architecture-diagram.png…]()
=======
# Cookies and JWT

Basic example of using JWTs and returning them via cookies. 

To test: 
1. Run `npm install`
2. Copy `config.js.stub` to `config.js` and edit if neccessary
3. Run using `npm start`
4. Send a `POST` to `http://localhost:8000/login` with username and password in a JSON body. If the username and password match the dummy values in `config.js`, the server will respond with `{"success": true}`, and a JWT stored as a cookie.
5. Send a `GET` to `http://localhost:8000/test`. The server will verify the JWT sent to it as a cookie, and return `{"success": true}` if it is valid.
>>>>>>> ac208d1 (first commit)
