var kvDw = $"https://{_appSettings.Value.DataWarehouseKeyVault}.vault.azure.net";
        var dwClient = new SecretClient(new Uri(kvDw), new DefaultAzureCredential());
        var connectionString = (await dwClient.GetSecretAsync("connection-string")).Value;

        var kvAzure = $"https://{_appSettings.Value.AzureAppsKeyVault}.vault.azure.net";
        var azClient = new SecretClient(new Uri(kvAzure), new DefaultAzureCredential());

        var accessToken = await GetAzureOAuthToken(azClient);

        string sqlConnectionString = connectionString.Value;
        List<JToken> jsonTransactionList = [];
        List<Users> enabledUsersList = [];
        List<Users> fullUserDetailsList = [];

        // Get all users from Azure
        var enabledUsers = await FetchEnabledUsers(
            "https://graph.microsoft.com/beta/users?$filter=accountEnabled eq true",
            accessToken,
            jsonTransactionList);

        enabledUsersList.AddRange(enabledUsers.Select(GetUserDetail));

        // Filter to only unique employeeID, include users with no employeeId.
        var enabledUsersListClean = enabledUsersList
            .Where(x => string.IsNullOrEmpty(x.employeeId) || int.TryParse(x.employeeId, out _));

        foreach (var user in enabledUsersListClean)
        {
            fullUserDetailsList.Add(await RetrieveManager(accessToken, user));
        }

        // Get ADP employee list from SQL
        List<Paylocity_Employee> paylocityEmployeeList;
        using (var sqlConn = GetSqlConnection(sqlConnectionString))
        {
            paylocityEmployeeList = (await GetEmployees(sqlConn)).OrderBy(x => x.EmployeeID).ToList();
        }

        var comparer = StringComparer.OrdinalIgnoreCase;
        var azureWorkEmailDict = fullUserDetailsList
            .Where(u => !string.IsNullOrEmpty(u.mail))
            .ToDictionary(p => p.mail!, comparer);

        var joinedData = from pe in paylocityEmployeeList
                         join au in fullUserDetailsList on pe.WorkEmail.ToLower() equals au.mail.ToLower() into azureGroup
                         from au in azureGroup.DefaultIfEmpty()
                         select new
                         {
                             Paylocity_Employee = pe,
                             Azure_User = au
                         };

        var paylocityAzureCompareList = joinedData.Where(r => r.Azure_User != null)
            .Select(r => new Paylocity_Azure_Compare
            {
                Paylocity_WorkEmail = r.Paylocity_Employee.WorkEmail,
                Paylocity_EmployeeID = r.Paylocity_Employee.EmployeeID,
                Paylocity_BusinessUnit = r.Paylocity_Employee.BusinessUnit,
                Paylocity_JobTitle = r.Paylocity_Employee.JobTitle,
                Paylocity_ReportsToEmail = r.Paylocity_Employee.ReportsToEmail,
                Paylocity_ReportsToEmployeeID = r.Paylocity_Employee.ReportsToEmployeeID,
                Paylocity_ReportsToAzureID = string.Empty,
                Azure_ID = r.Azure_User?.id ?? string.Empty,
                Azure_EmployeeID = r.Azure_User?.employeeId ?? string.Empty,
                Azure_Company = r.Azure_User?.companyName ?? string.Empty,
                Azure_JobTitle = r.Azure_User?.jobTitle ?? string.Empty,
                Azure_ManagerEmail = r.Azure_User?.manager_email ?? string.Empty,
                Azure_ManagerID = r.Azure_User?.manager_id ?? string.Empty,
            }).ToList();

        // Load azure id for paylocity manager assignment
        foreach (var item in paylocityAzureCompareList)
        {
            if (!string.IsNullOrEmpty(item.Paylocity_ReportsToEmployeeID))
            {
                var manager = paylocityAzureCompareList.FirstOrDefault(x => x.Paylocity_EmployeeID == item.Paylocity_ReportsToEmployeeID);
                if (manager != null)
                {
                    item.Paylocity_ReportsToAzureID = manager.Azure_ID;
                }
            }
        }

        // Find mismatches
        var fixJobTitles = paylocityAzureCompareList
            .Where(x => x.Paylocity_JobTitle != x.Azure_JobTitle && !string.IsNullOrEmpty(x.Azure_ID)).ToList();

        var fixManager = paylocityAzureCompareList
            .Where(x => !string.IsNullOrEmpty(x.Paylocity_ReportsToEmployeeID))
            .Where(y => !string.Equals(y.Paylocity_ReportsToEmail, y.Azure_ManagerEmail, StringComparison.OrdinalIgnoreCase))
            .Where(x => !string.IsNullOrEmpty(x.Azure_ID) && !string.IsNullOrEmpty(x.Paylocity_ReportsToAzureID)).ToList();

        var fixCompany = paylocityAzureCompareList
            .Where(x => x.Paylocity_BusinessUnit != x.Azure_Company && !string.IsNullOrEmpty(x.Azure_ID)).ToList();

        var fixEmployeeID = paylocityAzureCompareList
            .Where(x => x.Paylocity_EmployeeID != x.Azure_EmployeeID && !string.IsNullOrEmpty(x.Azure_ID)).ToList();

        // Update records if applicable with sanity check
        await CheckPerformJobTitleUpdates(apiUpdatedEnabled, sanityCheck, sanityCheckCount, sanityCheckDistribution, smtpServer, dwClient, fixJobTitles, accessToken);
        await CheckPerformEmployeeUpdates(apiUpdatedEnabled, sanityCheck, sanityCheckCount, sanityCheckDistribution, smtpServer, dwClient, fixEmployeeID, accessToken);
        await CheckPerformCompanyUpdates(apiUpdatedEnabled, sanityCheck, sanityCheckCount, sanityCheckDistribution, smtpServer, dwClient, fixCompany, accessToken);
        await CheckPerformManagerUpdates(apiUpdatedEnabled, sanityCheck, sanityCheckCount, sanityCheckDistribution, smtpServer, dwClient, fixManager, accessToken);