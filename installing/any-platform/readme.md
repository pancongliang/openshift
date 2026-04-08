## Red Hat Case Insight Agent
The **Red Hat Case Insight Agent** is an initial troubleshooting tool that generates a case response template.

## Architecture & Workflow

The agent follows a structured workflow to analyze and diagnose issues:

1. **User Input**  
   Symptom report (e.g., "OCP Node NotReady after JBoss spike")

2. **Diagnostic Extraction**  
   AI identifies the need to correlate JVM memory (JBoss) with Node resource pressure (RHEL)

3. **Context Retrieval**  
   Real-time KCS search via Hydra API for known OCP 4.x/RHEL bugs

4. **Deep-Dive Analysis**  
   Maps the must-gather pod logs to sosreport sar metrics to prove a resource-driven reboot

5. **Final Report**  
   Generates a 3-part report: **Systemic Analysis** → **Deep-Dive Reasoning** → **Strategic Action Plan**


## Installations

#### Install required Python libraries
```
pip3 install streamlit requests
```

#### Clone the repository and navigate to the project directory
```
git clone https://gitlab.cee.redhat.com/chanlee/case-triage-expert.git
cd case-triage-expert
```
#### Running the Application
Start the application with the following command. It will automatically open in your browser at http://localhost:8501
```
python -m streamlit run app.py
```

## Demo
#### [🎬 Watch the demo video](https://drive.google.com/file/d/1A92NebOjad7rSb1AgzTEgTQ-Drfq3cFs/view?usp=sharing)
