#!/bin/bash
# OAuth Testing Script for Coves Mobile
# This script helps verify the OAuth flow is working correctly

set -e

echo "🔍 Coves Mobile - OAuth Flow Test"
echo "=================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 1. Check environment configuration
echo "1️⃣  Checking environment configuration..."
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ .env file not found${NC}"
    exit 1
fi

source .env

if [ -z "$EXPO_PUBLIC_OAUTH_SERVER_URL" ]; then
    echo -e "${RED}❌ EXPO_PUBLIC_OAUTH_SERVER_URL not set${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Environment variables configured${NC}"
echo "   - OAuth Server: $EXPO_PUBLIC_OAUTH_SERVER_URL"
echo ""

# 2. Check client-metadata.json endpoint
echo "2️⃣  Checking client-metadata.json endpoint..."
CLIENT_METADATA_URL="${EXPO_PUBLIC_OAUTH_SERVER_URL}/client-metadata.json"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$CLIENT_METADATA_URL")

if [ "$HTTP_CODE" == "200" ]; then
    echo -e "${GREEN}✅ Client metadata endpoint accessible${NC}"
    echo "   Endpoint: $CLIENT_METADATA_URL"
    echo ""
    echo "   Metadata:"
    curl -s "$CLIENT_METADATA_URL" | python3 -m json.tool 2>/dev/null || curl -s "$CLIENT_METADATA_URL"
else
    echo -e "${RED}❌ Client metadata endpoint not accessible (HTTP $HTTP_CODE)${NC}"
    exit 1
fi
echo ""

# 3. Check TypeScript compilation
echo "3️⃣  Checking TypeScript compilation..."
if npx tsc --noEmit 2>&1 | grep -q "error TS"; then
    echo -e "${RED}❌ TypeScript errors found${NC}"
    npx tsc --noEmit
    exit 1
else
    echo -e "${GREEN}✅ No TypeScript errors${NC}"
fi
echo ""

# 4. Check app configuration
echo "4️⃣  Checking app.json configuration..."
if grep -q "\"scheme\":" app.json; then
    SCHEME=$(grep "\"scheme\":" app.json | cut -d'"' -f4)
    echo -e "${GREEN}✅ App scheme configured: $SCHEME${NC}"
else
    echo -e "${RED}❌ No app scheme found in app.json${NC}"
    exit 1
fi

if grep -q "\"intentFilters\":" app.json; then
    echo -e "${GREEN}✅ Android intent filters configured${NC}"
else
    echo -e "${YELLOW}⚠️  No Android intent filters found${NC}"
fi

if grep -q "\"associatedDomains\":" app.json; then
    echo -e "${GREEN}✅ iOS associated domains configured${NC}"
else
    echo -e "${YELLOW}⚠️  No iOS associated domains found${NC}"
fi
echo ""

# 5. Package versions
echo "5️⃣  Checking OAuth package versions..."
OAUTH_CLIENT_VERSION=$(npm list @atproto/oauth-client 2>/dev/null | grep @atproto/oauth-client | cut -d'@' -f3)
OAUTH_CLIENT_EXPO_VERSION=$(npm list @atproto/oauth-client-expo 2>/dev/null | grep @atproto/oauth-client-expo | cut -d'@' -f3)
API_VERSION=$(npm list @atproto/api 2>/dev/null | grep @atproto/api | cut -d'@' -f3)

echo "   - @atproto/oauth-client: $OAUTH_CLIENT_VERSION"
echo "   - @atproto/oauth-client-expo: $OAUTH_CLIENT_EXPO_VERSION"
echo "   - @atproto/api: $API_VERSION"
echo ""

# Summary
echo "=================================="
echo -e "${GREEN}✅ All pre-flight checks passed!${NC}"
echo ""
echo "📱 Next steps for testing:"
echo ""
echo "   For Android:"
echo "   $ npm run android"
echo ""
echo "   For iOS:"
echo "   $ npm run ios"
echo ""
echo "   Then test the OAuth flow:"
echo "   1. Tap 'Sign In' on the login screen"
echo "   2. Enter a valid atProto handle (e.g., user.bsky.social)"
echo "   3. Authorize in the browser"
echo "   4. Verify deep link returns to app"
echo "   5. Check that you're logged in"
echo ""
echo "   To test session persistence:"
echo "   1. Force close the app"
echo "   2. Reopen the app"
echo "   3. Verify you're still logged in"
echo ""
echo "🔧 Troubleshooting:"
echo "   - Clear app data: Use '[DEV] Clear Storage' button on login screen"
echo "   - Check logs: Use 'npx react-native log-android' or 'npx react-native log-ios'"
echo "   - Verify redirect URI matches in app.json and .env"
echo ""
