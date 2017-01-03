<%@ WebHandler Language="C#" Class="JiraHandler" %>

using System;
using System.IO;
using System.Net;
using System.Text;
using System.Web;
using Newtonsoft.Json.Linq;
using MarvalSoftware.UI.WebUI.ServiceDesk.RFP.Plugins;

/// <summary>
///JiraHandler
/// </summary>
public class JiraHandler : PluginHandler
{
    //Properties 
    private int MsmRequestNo { get; set; }

    private string JiraIssueNo { get; set; }

    private string JiraSummary { get; set; }

    private string JiraType { get; set; }

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
            return GlobalSettings["JIRABaseUrl"];
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

    /// <summary>
    /// Process Handler Request
    /// </summary>
    public override void HandleRequest(HttpContext context)
    {
        var param = context.Request.HttpMethod;

        MsmRequestNo = !string.IsNullOrWhiteSpace(context.Request.Params["requestNumber"]) ? int.Parse(context.Request.Params["requestNumber"]) : 0;
        JiraIssueNo = context.Request.Params["issueNumber"] ?? string.Empty;
        JiraSummary = context.Request.Params["issueSummary"] ?? string.Empty;
        JiraType = context.Request.Params["issueType"] ?? string.Empty;

        switch (param)
        {
            case "GET":
                var preReqCheck = context.Request.Params["preReq"] ?? string.Empty;
                if (string.IsNullOrWhiteSpace(preReqCheck))
                {
                    context.Response.Write(JiraRequestManager(String.Format("search?jql='{0}'={1}", this.CustomFieldName, this.MsmRequestNo)));
                }
                else
                {                
                    context.Response.Write(PreRequisiteCheck());
                }
                break;
            case "PUT":
                JiraRequestManager(String.Format("issue/{0}", JiraIssueNo), GenerateJson(param, this.MsmRequestNo), "PUT");
                context.Response.Write(JiraRequestManager(String.Format("issue/{0}", JiraIssueNo)));
                break;
            case "DELETE":
                context.Response.Write(JiraRequestManager(String.Format("issue/{0}", JiraIssueNo), GenerateJson(param), "PUT"));
                break;
            case "POST":
                dynamic result = JObject.Parse(JiraRequestManager("issue/", GenerateJson(param), "POST"));
                context.Response.Write(JiraRequestManager(String.Format("issue/{0}", result.key)));
                break;
        }
    }

    private JObject PreRequisiteCheck()
    {
        var preReqs =  new JObject();
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

    /// <summary>
    /// Generate JSON for Jira REST request
    /// </summary>
    private string GenerateJson(string verb, int value = 0)
    {
        if (verb == "POST")
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
                    }
                }
            });

            jobject.fields[this.CustomFieldId.ToString()] = this.MsmRequestNo;
            return jobject.ToString();
        }
        else if (verb == "PUT")
        {
            return new JObject(new JProperty("fields", new JObject(new JProperty(this.CustomFieldId, value)))).ToString();
        }
        else
        {
            return new JObject(new JProperty("fields", new JObject(new JProperty(this.CustomFieldId, null)))).ToString();
        }
    }

    /// <summary>
    /// Process the Jira REST request
    /// </summary>
    private string JiraRequestManager(string argument = null, string data = null, string method = "GET")
    {
        var url = this.BaseUrl + "rest/api/2/";

        if (argument != null)
        {
            url = String.Format("{0}{1}", url, argument);
        }

        HttpWebRequest request = WebRequest.Create(url) as HttpWebRequest;
        request.ContentType = "application/json";
        request.Method = method;

        if (data != null)
        {
            using (var writer = new StreamWriter(request.GetRequestStream()))
            {
                writer.Write(data);
            }
        }

        var base64Credentials = GetEncodedCredentials();
        request.Headers.Add("Authorization", "Basic " + base64Credentials);

        HttpWebResponse response = request.GetResponse() as HttpWebResponse;

        string result;
        using (StreamReader reader = new StreamReader(response.GetResponseStream()))
        {
            result = reader.ReadToEnd();
        }

        return result;
    }

    /// <summary>
    /// Get base64 encoded details
    /// </summary>
    private string GetEncodedCredentials()
    {
        string mergedCredentials = String.Format("{0}:{1}", this.Username, this.Password);
        byte[] byteCredentials = Encoding.UTF8.GetBytes(mergedCredentials);
        return Convert.ToBase64String(byteCredentials);
    }

    public override bool IsReusable
    {
        get { return false; }
    }
}



