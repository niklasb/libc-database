import React, { useCallback, useMemo, useState } from 'react';
import './App.css';
import '@fontsource/roboto/400.css';
import {
  Box,
  Button,
  CircularProgress,
  Grid,
  Link,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableRow,
  TextField,
} from '@mui/material';


const API_BASE = 'https://libc.rip/api';

const api = async (path, data) => {
  let resp = await fetch(`${API_BASE}${path}`, {
    method: 'POST',
    mode: 'cors',
    cache: 'no-cache',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(data),
  });
  return await resp.json();
};

const createRow = () => ({
  id: globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(16).slice(2)}`,
  symbol: '',
  address: '',
  addressValid: true,
});

const isHexAddress = (value) => /^(0x)?[0-9a-fA-F]*$/.test(value);

const isEmptyRow = (row) => !row.symbol && !row.address;

const normalizeRows = (rows) => {
  if (rows.length === 0) {
    return [createRow()];
  }

  let nextRows = rows;

  while (
    nextRows.length > 1 &&
    isEmptyRow(nextRows[nextRows.length - 1]) &&
    isEmptyRow(nextRows[nextRows.length - 2])
  ) {
    nextRows = nextRows.slice(0, -1);
  }

  if (!isEmptyRow(nextRows[nextRows.length - 1])) {
    nextRows = nextRows.concat(createRow());
  }

  return nextRows;
};


function SearchRow({ symbol, address, addressValid, onSymbolChange, onAddressChange, onRemove }) {
  const handleSymbolChange = useCallback((evt) => {
    onSymbolChange(evt.target.value);
  }, [onSymbolChange]);

  const handleAddressChange = useCallback((evt) => {
    const value = evt.target.value;
    onAddressChange(value, isHexAddress(value));
  }, [onAddressChange]);

  return (
    <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1.5} sx={{ alignItems: 'flex-start' }}>
      <TextField
        fullWidth
        label="Symbol name"
        value={symbol}
        onChange={handleSymbolChange}
        size="small"
      />
      <TextField
        fullWidth
        label="Address"
        error={!addressValid}
        value={address}
        onChange={handleAddressChange}
        size="small"
      />
      <Button variant="outlined" color="secondary" onClick={onRemove} sx={{ mt: { xs: 0, sm: '2px' } }}>
        Remove
      </Button>
    </Stack>
  );
}

function SearchForm({ onSearch = () => {} }) {
  const [rows, setRows] = useState(() => [createRow()]);

  const updateRow = useCallback((id, patch) => {
    setRows((currentRows) => {
      const nextRows = currentRows.map((row) => (
        row.id === id
          ? {
              ...row,
              ...patch,
              addressValid: patch.address !== undefined ? isHexAddress(patch.address) : row.addressValid,
            }
          : row
      ));

      return normalizeRows(nextRows);
    });
  }, []);

  const removeRow = useCallback((id) => {
    setRows((currentRows) => normalizeRows(currentRows.filter((row) => row.id !== id)));
  }, []);

  const onSubmit = useCallback(() => {
    let symbols = {};
    for (let row of rows) {
      if (row.addressValid && row.address && row.symbol) {
        symbols[row.symbol] = row.address;
      }
    }
    onSearch({"symbols": symbols});
  }, [rows, onSearch]);

  const isValid = useMemo(() => {
    let count = 0;
    for (let row of rows) {
      if (!row.addressValid) {
        return false;
      }
      if (row.address && row.symbol) {
        count += 1;
      }
    }
    return count > 0;
  }, [rows]);

  return (
    <Box component="form" sx={{ display: 'grid', gap: 2 }}>
      {rows.map((row) => (
        <SearchRow
          key={row.id}
          symbol={row.symbol}
          address={row.address}
          addressValid={row.addressValid}
          onSymbolChange={(symbol) => updateRow(row.id, { symbol })}
          onAddressChange={(address, addressValid) => updateRow(row.id, { address, addressValid })}
          onRemove={() => removeRow(row.id)}
        />
      ))}

      <div>
        <Button
          disabled={!isValid}
          variant="contained"
          type="button"
          className="findbutton"
          color="primary"
          onClick={onSubmit}>
          Find
        </Button>
      </div>
    </Box>
  );
}

function Result({ id, buildid, md5, symbols, download_url, symbols_url }) {
  const [open, setOpen] = useState(false);

  const onToggle = useCallback((evt) => {
    evt.preventDefault();
    setOpen((value) => !value);
  }, []);

  const symbolRows = Object.entries(symbols ?? {}).map(([k, v]) => (
    <TableRow key={k}>
      <TableCell><code>{k}</code></TableCell>
      <TableCell><code>{v}</code></TableCell>
    </TableRow>
  ));

  return (
    <Box sx={{ mb: 1 }}>
      <Link href='#' onClick={onToggle}>{id}</Link>
      {open && (
        <Table size="small" sx={{ mt: 1, mb: 2 }}>
          <TableBody>
            <TableRow>
              <TableCell>Download</TableCell>
              <TableCell>
                <Link href={download_url} download>Click to download</Link>
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>All Symbols</TableCell>
              <TableCell>
                <Link href={symbols_url} download>Click to download</Link>
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>BuildID</TableCell>
              <TableCell>{buildid}</TableCell>
            </TableRow>
            <TableRow>
              <TableCell>MD5</TableCell>
              <TableCell>{md5}</TableCell>
            </TableRow>
            {symbolRows}
          </TableBody>
        </Table>
      )}
    </Box>
  );
}

function App() {
  const [loading, setLoading] = useState(false);
  const [results, setResults] = useState(null);

  const onSearch = (data) => {
    setLoading(true);
    (async () => {
      try {
        setResults(await api('/find', data));
      } finally {
        setLoading(false);
      }
    })();
  };

  return (
    <div className="App">
      <p>
        Powered by the{' '}
        <Link href="https://github.com/niklasb/libc-database/tree/master/searchengine">
          libc-database search API
        </Link>
      </p>

      <Grid container spacing={2}>
        <Grid item xs={12} md={6}>
          <h3>Search</h3>
          <SearchForm onSearch={onSearch} />
        </Grid>
        <Grid item xs={12} md={6}>
          <h3>Results</h3>
          {loading && <CircularProgress />}
          {results !== null && results.map((x) => <Result key={x.id} {...x} />)}
        </Grid>
      </Grid>
    </div>
  );
}

export default App;