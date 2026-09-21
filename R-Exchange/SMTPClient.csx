static async Task Main(string[] args)
{
    try
    {
        var token = await GetAzureOAuthToken();
        SendEmail(token);
        Console.WriteLine("Email sent successfully.");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Error sending email: {ex.Message}");
    }
}
 
 
private static async Task<string> GetAzureOAuthToken()
{
    var tenantId = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6";
    string entraAppId = "96b011fd-9d27-4d9d-b813-078a17c8a35f";
    string entraAppClientSecret = "removed for security reasons";
    string entraAuthority = $"https://login.microsoftonline.com/{tenantId}";
 
    string client_id = entraAppId ?? throw new InvalidOperationException("clientId is null");
    string tenant_id = tenantId ?? throw new InvalidOperationException("tenant-id is null");
    string client_secret = entraAppClientSecret ?? throw new InvalidOperationException("clientSecret is null");
 
    // Build the MSAL confidential client application
    IConfidentialClientApplication app = ConfidentialClientApplicationBuilder
        .Create(entraAppId)
        .WithClientSecret(entraAppClientSecret)
        .WithAuthority(new Uri(entraAuthority))
        .WithTenantId(tenantId)
        .Build();
 
    // Define the resource scope
    string[] scopes = new string[] { "https://outlook.office365.com/.default" };
 
    // Acquire token for the client
    AuthenticationResult result = await app.AcquireTokenForClient(scopes)
        .ExecuteAsync();
 
    return result.AccessToken;
}
 
 
private static void SendEmail(string token)
{
    // Microsoft Entra ID (Azure AD) credentials
    string smtpUsername = "SSRSreport@enchantedrock.com";
    string smtpHostUrl = "outlook.office365.com";
 
    string senderAddress = smtpUsername;
    string recipientAddress = "Jbastian@erock.com";
 
    string subject = "Test email sent using OAuth";
    string body = "This email message is sent from Azure Communication Service Email using SMTP.";
 
    var message = new MimeMessage();
    message.From.Add(new MailboxAddress("Sender Name", senderAddress));
    message.To.Add(new MailboxAddress("Recipient Name", recipientAddress));
    message.Subject = subject;
    message.Body = new TextPart("plain")
    {
        Text = body
    };
 
    using (var client = new SmtpClient())
    {
        client.Connect(smtpHostUrl, 587, SecureSocketOptions.StartTls);
 
        // Use the access token to authenticate
        
        var oauth2 = new SaslMechanismOAuth2(smtpUsername, token);
        client.Authenticate(oauth2);
 
        client.Send(message);
        client.Disconnect(true);
    }
}

