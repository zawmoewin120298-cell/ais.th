exports.handler = async (event) => {
    const data = {
        message: "Data Package API",
        timestamp: new Date().toISOString(),
        data: [
            { id: 1, name: "Item 1", price: 100 },
            { id: 2, name: "Item 2", price: 200 },
            { id: 3, name: "Item 3", price: 300 }
        ]
    };
    
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify(data)
    };
};
