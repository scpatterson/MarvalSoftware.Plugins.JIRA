<%@ WebHandler Language="C#" Class="ApiHandler" %>

using System;
using System.IO;
using System.Net;
using System.Text;
using System.Web;
using System.Dynamic;
using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using MarvalSoftware.UI.WebUI.ServiceDesk.RFP.Plugins;

/// <summary>
/// ApiHandler
/// </summary>
public class ApiHandler : PluginHandler
{
    //properties
    private string ProjectName
    {
        get
        {
            return GlobalSettings["JIRAProject"];
        }
    }

    private string CustomFieldName
    {
        get
        {
            return GlobalSettings["JIRACustomFieldName"];
        }
    }

    private string CustomFieldId
    {
        get
        {
            return GlobalSettings["JIRACustomFieldID"];
        }
    }

    private string BaseUrl
    {
        get
        {
            return GlobalSettings["JIRABaseUrl"] + "rest/api/latest/";
        }
    }

    private string MSMBaseUrl
    {
        get
        {
            return HttpContext.Current.Request.Url.Scheme + "://127.0.0.1" + MarvalSoftware.UI.WebUI.ServiceDesk.WebHelper.ApplicationPath;
        }
    }

    private string MSMAPIKey
    {
        get
        {
            return GlobalSettings["MSMAPIKey"];
        }
    }

    private string Username
    {
        get
        {
            return GlobalSettings["JIRAUsername"];
        }
    }

    private string Password
    {
        get
        {
            return GlobalSettings["JIRAPassword"];
        }
    }

    private string JiraCredentials
    {
        get
        {
            return GetEncodedCredentials(String.Format("{0}:{1}", this.Username, this.Password));
        }
    }

    private string JiraIssueNo { get; set; }

    private string JiraSummary { get; set; }

    private string JiraType { get; set; }

    //fields
    private int MsmRequestNo;


    /// <summary>
    /// Handle Request
    /// </summary>
    public override void HandleRequest(HttpContext context)
    {
        ProcessParamaters(context.Request);

        var action = context.Request.QueryString["action"];
        RouteRequest(action, context);
    }

    public override bool IsReusable
    {
        get { return false; }
    }

    /// <summary>
    /// Get Paramaters from QueryString
    /// </summary>
    private void ProcessParamaters(HttpRequest httpRequest)
    {
        int.TryParse(httpRequest.Params["requestNumber"], out MsmRequestNo);
        JiraIssueNo = httpRequest.Params["issueNumber"] ?? string.Empty;
        JiraSummary = httpRequest.Params["issueSummary"] ?? string.Empty;
        JiraType = httpRequest.Params["issueType"] ?? string.Empty;
    }

    /// <summary>
    /// Route Request via Action
    /// </summary>
    private void RouteRequest(string action, HttpContext context)
    {
        HttpWebRequest httpWebRequest;

        switch (action)
        {
            case "PreRequisiteCheck":
                context.Response.Write(PreRequisiteCheck());
                break;
            case "GetJiraIssues":
                httpWebRequest = BuildRequest(this.BaseUrl + String.Format("search?jql='{0}'={1}", this.CustomFieldName, this.MsmRequestNo));
                context.Response.Write(ProcessRequest(httpWebRequest, this.JiraCredentials));
                break;
            case "LinkJiraIssue":
                UpdateJiraIssue(this.MsmRequestNo);
                httpWebRequest = BuildRequest(this.BaseUrl + String.Format("issue/{0}", JiraIssueNo));
                context.Response.Write(ProcessRequest(httpWebRequest, this.JiraCredentials));
                break;
            case "UnlinkJiraIssue":
                context.Response.Write(UpdateJiraIssue(null));
                break;
            case "CreateJiraIssue":
                dynamic result = CreateJiraIssue();
                httpWebRequest = BuildRequest(this.BaseUrl + String.Format("issue/{0}", result.key));
                context.Response.Write(ProcessRequest(httpWebRequest, this.JiraCredentials));
                break;
            case "MoveStatus":
                MoveMsmStatus(context.Request);
                break;
            case "AddNote":
                httpWebRequest = BuildRequest(this.BaseUrl + String.Format("search?jql=id={0}", context.Request.QueryString["issue"]));

                string webhookJson = new StreamReader(context.Request.InputStream).ReadToEnd();
                dynamic webhookData = JObject.Parse(webhookJson);
                string commentBody = webhookData.comment.body.Value;

                var issueJson = JObject.Parse(ProcessRequest(httpWebRequest, this.JiraCredentials));
                int requestId = Int32.Parse((string)issueJson["issues"].First["fields"][this.CustomFieldId.ToString()]);

                AddMsmNote(requestId,  commentBody);
                break;

        }
    }

    /// <summary>
    /// Create New Jira Issue
    /// </summary>
    private JObject CreateJiraIssue()
    {
        dynamic jobject = JObject.FromObject(new
        {
            fields = new
            {
                project = new
                {
                    key = this.ProjectName
                },
                summary = this.JiraSummary,
                issuetype = new
                {
                    name = this.JiraType
                },
            }
        });
        jobject.fields[this.CustomFieldId.ToString()] = this.MsmRequestNo;

        var httpWebRequest = BuildRequest(this.BaseUrl + "issue/", jobject.ToString(), "POST");
        return JObject.Parse(ProcessRequest(httpWebRequest, this.JiraCredentials));
    }

    /// <summary>
    /// Update Jira Issue
    /// </summary>
    /// <param name="value">Value to update custom field in JIRA with</param>
    /// <returns>Process Response</returns>
    private string UpdateJiraIssue(int? value)
    {
        IDictionary<string, object> body = new Dictionary<string, object>();
        IDictionary<string, object> result = new Dictionary<string, object>();
        result.Add(this.CustomFieldId, value);
        body.Add("fields", result);

        var httpWebRequest = BuildRequest(this.BaseUrl + String.Format("issue/{0}", JiraIssueNo), JsonHelper.ToJSON(body), "PUT");
        return ProcessRequest(httpWebRequest, this.JiraCredentials);
    }

    /// <summary>
    /// Move MSM Status
    /// </summary>
    /// <param name="httpRequest">The HttpRequest</param>
    /// <returns>Process Response</returns>
    private void MoveMsmStatus(HttpRequest httpRequest)
    {
        int requestNumber;
        var isValid = StatusValidation(httpRequest, out requestNumber);

        HttpWebRequest httpWebRequest;
        httpWebRequest = BuildRequest(this.MSMBaseUrl + String.Format("/api/serviceDesk/operational/requests?number={0}", requestNumber));
        var requestResponse = JObject.Parse(ProcessRequest(httpWebRequest, GetEncodedCredentials(this.MSMAPIKey)));
        var requestId = (int)requestResponse["items"].First["id"];

        if (isValid)
        {
            httpWebRequest = BuildRequest(this.MSMBaseUrl + String.Format("/api/serviceDesk/administration/states?name={0}", httpRequest.QueryString["status"]));
            var statusResponse = JObject.Parse(ProcessRequest(httpWebRequest, GetEncodedCredentials(this.MSMAPIKey)));

            string response = string.Empty;
            if ((int)statusResponse["totalItemCount"] > 0)
            {
                dynamic msmPutRequest = new ExpandoObject();
                msmPutRequest.statusId = (int)statusResponse["items"]["entity"]["data"].First["id"];
                msmPutRequest.updatedOn = (DateTime)requestResponse["items"]["entity"]["data"].First["updatedOn"];

                httpWebRequest = BuildRequest(this.MSMBaseUrl + String.Format("/api/serviceDesk/operational/requests/{0}/states", requestId), JsonHelper.ToJSON(msmPutRequest), "POST");

                response = ProcessRequest(httpWebRequest, GetEncodedCredentials(this.MSMAPIKey));
            }

            if (response.Contains("404") || (int)statusResponse["totalItemCount"] == 0)
            {
                AddMsmNote(requestId, "JIRA status update failed: " + httpRequest.QueryString["status"] + " is not a valid next state.");
            }

        }
        else
        {
            AddMsmNote(requestId,  "JIRA status update failed: all linked JIRA issues must be in the same status.");
        }
    }

    /// <summary>
    /// Add MSM Note
    /// </summary>   
    private void AddMsmNote(int requestNumber, string note)
    {
        IDictionary<string, object> body = new Dictionary<string, object>();
        body.Add("id", requestNumber);
        body.Add("content", note);

        HttpWebRequest httpWebRequest;
        httpWebRequest = BuildRequest(this.MSMBaseUrl + String.Format("/api/serviceDesk/operational/requests/{0}/notes/", requestNumber), JsonHelper.ToJSON(body), "POST");
        ProcessRequest(httpWebRequest, GetEncodedCredentials(this.MSMAPIKey));
    }

    /// <summary>
    /// Validate before moving MSM status
    /// </summary>
    /// <param name="httpRequest">The HttpRequest</param>
    /// <returns>Boolean to determine if Valid</returns>
    private bool StatusValidation(HttpRequest httpRequest, out int requestNumber)
    {
        string json = new StreamReader(httpRequest.InputStream).ReadToEnd();
        dynamic data = JObject.Parse(json);
        requestNumber = (int)data.issue.fields[this.CustomFieldId].Value;

        if (requestNumber > 0 && httpRequest.QueryString["status"] != null)
        {
            var httpWebRequest = BuildRequest(this.BaseUrl + String.Format("search?jql='{0}'={1}", this.CustomFieldName, requestNumber));
            dynamic d = JObject.Parse(ProcessRequest(httpWebRequest, this.JiraCredentials));
            foreach (var issue in d.issues)
            {
                if (issue.fields.status.name.Value != data.transition.to_status.Value)
                {
                    return false;
                }
            }

            return true;
        }
        else
        {
            return false;
        }
    }


    /// <summary>
    /// Check and return missing plugin settings
    /// </summary>
    /// <returns>Json Object containing any settings that failed the check</returns>
    private JObject PreRequisiteCheck()
    {
        var preReqs = new JObject();
        if (string.IsNullOrWhiteSpace(this.ProjectName))
        {
            preReqs.Add("jiraProject", false);
        }
        if (string.IsNullOrWhiteSpace(this.CustomFieldName))
        {
            preReqs.Add("jiraCustomFieldName", false);
        }
        if (string.IsNullOrWhiteSpace(this.CustomFieldId))
        {
            preReqs.Add("jiraCustomFieldID", false);
        }
        if (string.IsNullOrWhiteSpace(this.BaseUrl))
        {
            preReqs.Add("jiraBaseUrl", false);
        }
        if (string.IsNullOrWhiteSpace(this.Username))
        {
            preReqs.Add("jiraUsername", false);
        }
        if (string.IsNullOrWhiteSpace(this.Password))
        {
            preReqs.Add("jiraPassword", false);
        }

        return preReqs;
    }

    //Generic Methods

    /// <summary>
    /// Builds a HttpWebRequest
    /// </summary>
    /// <param name="uri">The uri for request</param>
    /// <param name="body">The body for the request</param>
    /// <param name="method">The verb for the request</param>
    /// <returns>The HttpWebRequest ready to be processed</returns>
    private static HttpWebRequest BuildRequest(string uri = null, string body = null, string method = "GET")
    {
        var request = WebRequest.Create(new UriBuilder(uri).Uri) as HttpWebRequest;
        request.Method = method.ToUpperInvariant();
        request.ContentType = "application/json";

        if (body != null)
        {
            using (var writer = new StreamWriter(request.GetRequestStream()))
            {
                writer.Write(body);
            }
        }

        return request;
    }

    /// <summary>
    /// Proccess a HttpWebRequest
    /// </summary>
    /// <param name="request">The HttpWebRequest</param>
    /// <param name="credentials">The Credentails to use for the API</param>
    /// <returns>Process Response</returns>
    private static string ProcessRequest(HttpWebRequest request, string credentials)
    {
        try
        {
            request.Headers.Add("Authorization", "Basic " + credentials);

            HttpWebResponse response = request.GetResponse() as HttpWebResponse;
            using (StreamReader reader = new StreamReader(response.GetResponseStream()))
            {
                return reader.ReadToEnd();
            }
        }
        catch (WebException ex)
        {
            return ex.Message;
        }

    }

    /// <summary>
    /// Encodes Credentials
    /// </summary>
    /// <param name="credentials">The string to encode</param>
    /// <returns>base64 encoded string</returns>
    private string GetEncodedCredentials(string credentials)
    {
        byte[] byteCredentials = Encoding.UTF8.GetBytes(credentials);
        return Convert.ToBase64String(byteCredentials);
    }

    /// <summary>
    /// JsonHelper Functions
    /// </summary>
    internal class JsonHelper
    {
        public static string ToJSON(object obj)
        {
            return JsonConvert.SerializeObject(obj);
        }
    }
}